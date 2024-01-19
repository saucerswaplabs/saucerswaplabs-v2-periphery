// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.12;
pragma abicoder v2;

import '@saucerswaplabs/saucerswap-v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@saucerswaplabs/saucerswap-v3-core/contracts/libraries/FixedPoint128.sol';
import '@saucerswaplabs/saucerswap-v3-core/contracts/libraries/FullMath.sol';
import '@saucerswaplabs/saucerswap-v3-core/contracts/libraries/SafeCast.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/IHederaTokenService.sol';
import './libraries/PositionKey.sol';
import './libraries/PoolAddress.sol';
import './libraries/Bits.sol';
import './libraries/NFTHelper.sol';
import './libraries/HexStrings.sol';
import './base/LiquidityManagement.sol';
import './base/PeripheryImmutableState.sol';
import './base/Multicall.sol';
import './base/PeripheryValidation.sol';
import './base/PoolInitializer.sol';

/// @title NFT positions
/// @notice Uses Hedera NFT as a receipt token for Uniswap V3 positions
contract NonfungiblePositionManager is
    INonfungiblePositionManager,
    Multicall,
    PeripheryImmutableState,
    PoolInitializer,
    LiquidityManagement,
    PeripheryValidation
{
    using Bits for uint;
    using SafeCast for uint256;

    error CF(int respCode);
    // details about the uniswap position
    struct Position {
        // the pool id
        uint80 poolId;
        // the tick range of the position
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // how many uncollected tokens are owed to the position, as of the last computation
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @dev IDs of pools assigned by this contract
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The tokenSN position data
    mapping(uint256 => Position) private _positions;

    /// @dev The SN of the next token that will be minted. Skips 0
    uint256 private _nextSN = 1;
    /// @dev The SN of the next pool that is used for the first time. Skips 0
    uint80 private _nextPoolId = 1;

    address public override nft;
    address public override deployer;
    bool public override onlyOnce = true; 
    string public override baseUrl = "https://ssv2.io/";

    constructor(
        address _factory,
        address _WHBAR
    ) PeripheryImmutableState(_factory, _WHBAR) {
        deployer = msg.sender;
        // first position is all zeros - there is no corresponding NFT serial number 0
        _positions[0] = Position({
            poolId: 0,
            tickLower: 0,
            tickUpper: 0,
            liquidity: 0,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
    }

    /// @dev This function must be called before managing positions
    function createNonFungible(address _rentPayer, int64 _autoRenewPeriod) external payable override {
        require(msg.sender == deployer, 'only deployer can create NFT');
        require(onlyOnce, 'NFT already created');

        if (_rentPayer == address(0)) _rentPayer = address(this);

        uint supplyKeyType;
        IHederaTokenService.KeyValue memory supplyKeyValue;

        supplyKeyType = supplyKeyType.setBit(4);
        supplyKeyValue.contractId = address(this);

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](1);
        keys[0] = IHederaTokenService.TokenKey (supplyKeyType, supplyKeyValue);
        
        IHederaTokenService.Expiry memory expiry;
        expiry.autoRenewAccount = _rentPayer;
        expiry.autoRenewPeriod = _autoRenewPeriod;

        IHederaTokenService.HederaToken memory token;
        token.name = 'SaucerSwap v2 Liquidity Position';
        token.symbol = 'SSV2-LP';
        token.treasury = address(this);
        token.tokenSupplyType = false; // set supply to INFINITE
        token.tokenKeys = keys;
        token.expiry = expiry;

        address precompileAddress = address(0x167);

        (bool success, bytes memory result) = precompileAddress.call{value: msg.value}(
            abi.encodeWithSelector(IHederaTokenService.createNonFungibleToken.selector, token));
        (int responseCode, address tokenAddress) = success ? abi.decode(result, (int32, address)) : (int(21), address(0));

        if(responseCode != 22){
            revert CF(responseCode);
        }

        nft = tokenAddress;
        onlyOnce = false;
    }

    /// @inheritdoc INonfungiblePositionManager
    function positions(uint256 tokenSN)
        external
        view
        override
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenSN];
        require(position.poolId != 0, 'Invalid token ID');
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        return (
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @dev Caches a pool key
    function cachePoolKey(address pool, PoolAddress.PoolKey memory poolKey) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    function mint(MintParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 tokenSN,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {

        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        tokenSN = _nextSN++;

        { // stack too deep
        bytes memory metadataBytes = abi.encodePacked(baseUrl, HexStrings.toHexStringNoPrefix(tokenSN, 7)); // 14 digits in the url
        require(metadataBytes.length <= 100, 'metadata too long');

        bytes[] memory array = new bytes[](1);
        array[0] = metadataBytes;
        NFTHelper.safeMintTokens(nft, 0, array);
        IERC721(nft).transferFrom(address(this), params.recipient, tokenSN);
        }
        
        bytes32 positionKey = PositionKey.compute(address(this), params.tickLower, params.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // idempotent set
        uint80 poolId = cachePoolKey(
            address(pool),
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee})
        );

        _positions[tokenSN] = Position({
            poolId: poolId,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        emit IncreaseLiquidity(tokenSN, liquidity, amount0, amount1);
    }

    modifier isAuthorizedForToken(uint256 tokenSN) {
        address owner = IERC721(nft).ownerOf(tokenSN);
        require(
            IERC721(nft).isApprovedForAll(owner, msg.sender) || 
            msg.sender == owner ||
            IERC721(nft).getApproved(tokenSN) == msg.sender,
            'not authorized'
        );
        _;
    }

    /// @inheritdoc INonfungiblePositionManager
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {

        Position storage position = _positions[params.tokenSN];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this)
            })
        );

        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);

        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        unchecked {
            position.tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );
            position.tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
            position.liquidity += liquidity;
        }
        

        emit IncreaseLiquidity(params.tokenSN, liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenSN)
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.liquidity > 0);
        Position storage position = _positions[params.tokenSN];

        uint128 positionLiquidity = position.liquidity;
        require(positionLiquidity >= params.liquidity);

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');

        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);
        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        unchecked {
            position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );
            position.tokensOwed1 +=
                uint128(amount1) +
                uint128(
                    FullMath.mulDiv(
                        feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                        positionLiquidity,
                        FixedPoint128.Q128
                    )
                );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
            // subtraction is safe because we checked positionLiquidity is gte params.liquidity
            position.liquidity = positionLiquidity - params.liquidity;
        }

        emit DecreaseLiquidity(params.tokenSN, params.liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    function collect(CollectParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenSN)
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        // allow collecting to the nft position manager address with address 0
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        Position storage position = _positions[params.tokenSN];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(
                PositionKey.compute(address(this), position.tickLower, position.tickUpper)
            );

            unchecked {
                tokensOwed0 += uint128(
                    FullMath.mulDiv(
                        feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                        position.liquidity,
                        FixedPoint128.Q128
                    )
                );
                tokensOwed1 += uint128(
                    FullMath.mulDiv(
                        feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                        position.liquidity,
                        FixedPoint128.Q128
                    )
                );

                position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
                position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
            }
            
        }

        // compute the arguments to give to the pool#collect method
        (uint128 amount0Collect, uint128 amount1Collect) = (
            params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
            params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
        );

        // the actual amounts collected are returned
        (amount0, amount1) = pool.collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
        // instead of the actual amount so we can burn the token
        unchecked {
            (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);
        }
        
        emit Collect(params.tokenSN, recipient, amount0Collect, amount1Collect);
    }

    /// @inheritdoc INonfungiblePositionManager
    function burn(uint256 tokenSN) external payable override isAuthorizedForToken(tokenSN) {

        // must transfer NFT to this contract (treasury) to burn it
        Position storage position = _positions[tokenSN];
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, 'Not cleared');
        delete _positions[tokenSN];

        NFTHelper.safeTransferNFT(nft, msg.sender, address(this), tokenSN.toInt64());

        int64[] memory array = new int64[](1);
        array[0] = tokenSN.toInt64();
        NFTHelper.safeBurnTokens(nft, 0, array);

        emit Burn(tokenSN, msg.sender);
    }

}