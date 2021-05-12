pragma solidity 0.6.7;

import "./GebUniswapV3ManagerBase.sol";


abstract contract OracleLike {
    function priceSource() virtual public view returns (address);
    function getResultWithValidity() virtual public view returns (uint256, bool);
}
 abstract contract OracleRelayerLike {
    function redemptionPrice() virtual public returns (uint256);
    function collateralTypes(bytes32) virtual public view returns (
        OracleLike orcl,
        uint256 safetyCRatio,
        uint256 liquidationCRatio
    );
}
contract GebUniswapV3OracleAdapter is OracleForUniswapLike {


    // --- Constants ---
    uint256 constant WAD_COMPLEMENT = 10 ** 9;
    OracleRelayerLike immutable oracleRelayer;
    bytes32 immutable collateral;


    /**
     * @notice Constructor that sets initial parameters for this contract
     * @param _oracleRelayer The address of the oracleRelayer
     * @param _collateral The collateral for this oracle
     */
    constructor(OracleRelayerLike _oracleRelayer, bytes32 _collateral) public {
        oracleRelayer = _oracleRelayer;
        collateral = _collateral;
    }

     /**
     * @notice Function to get both prices from this oracle
     * @return redemptionPrice a WAD representing the redemption price
     * @return collateralPrice a WAD representing the collateral price
     * @return valid a boolean indicating weather the contract is valid
     */
    function getResultsWithValidity() public override returns (uint256, uint256, bool){
        uint256 redemptionPrice = oracleRelayer.redemptionPrice();

        (OracleLike priceSource, , ) = oracleRelayer.collateralTypes(collateral);

        (uint256 collateralPrice, bool valid) = priceSource.getResultWithValidity();
        require(valid, "GebUniswapv3LiquidityManager/invalid-col-price-feed");

        return (redemptionPrice / WAD_COMPLEMENT, collateralPrice, true);

    }

}