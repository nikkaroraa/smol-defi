// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

/**
 * @title interest rate models for lending protocols
 * @notice this contract implements three different interest rate models commonly used in defi lending protocols
 *
 * 1. linear model
 *    - simplest form of interest rate calculation
 *    - rate increases linearly with utilization
 *    - formula: rate = base_rate + (utilization * multiplier)
 *    - best for: stable markets with predictable utilization
 *    - example: at 50% utilization with base_rate=2% and multiplier=20%
 *      rate = 2% + (50% * 20%) = 12%
 *
 * 2. kink model (compound-style)
 *    - two-slope model with a kink point
 *    - normal slope until kink point, steeper slope after
 *    - formula:
 *      if utilization <= kink:
 *          rate = base_rate + (utilization * multiplier)
 *      else:
 *          rate = base_rate + (kink * multiplier) +
 *                 ((utilization - kink) * jump_multiplier)
 *    - best for: markets needing protection against high utilization
 *    - example: at 90% utilization with kink=80%:
 *      normal_rate = 2% + (80% * 20%) = 18%
 *      excess_rate = (90% - 80%) * 100% = 10%
 *      total_rate = 28%
 *
 * 3. exponential model
 *    - rate increases exponentially with utilization
 *    - current implementation uses square function
 *    - formula: rate = base_rate + (utilization² * multiplier)
 *    - best for: markets needing strong utilization incentives
 *    - example: at 50% utilization:
 *      rate = 2% + (50%² * 20%) = 7%
 *
 * @dev all rates are in basis points (1 basis point = 0.01%)
 * @dev utilization is calculated as: (total_borrowed / total_supplied) * 10000
 */
contract InterestRateModel {
    // model parameters
    uint256 public constant BASE_RATE = 200; // 2% in basis points
    uint256 public constant MULTIPLIER = 2000; // 20% in basis points
    uint256 public constant JUMP_MULTIPLIER = 10000; // 100% in basis points
    uint256 public constant KINK = 8000; // 80% in basis points
    uint256 public constant EXPONENT = 2; // for exponential model

    // model type enum
    enum ModelType {
        Linear,
        Kink,
        Exponential
    }

    ModelType public currentModel;

    event ModelChanged(ModelType newModel);
    event InterestRateCalculated(uint256 utilization, uint256 rate);

    constructor(ModelType _initialModel) {
        currentModel = _initialModel;
    }

    /**
     * @notice calculate utilization rate
     * @param _borrowAmount total amount borrowed
     * @param _totalSupply total amount supplied
     * @return utilization rate in basis points (1 = 0.01%)
     */
    function calculateUtilization(uint256 _borrowAmount, uint256 _totalSupply) public pure returns (uint256) {
        if (_totalSupply == 0) return 0;
        return (_borrowAmount * 10000) / _totalSupply; // returns in basis points
    }

    /**
     * @notice linear interest rate model
     * @param utilization utilization rate in basis points
     * @return interest rate in basis points
     */
    function getLinearRate(uint256 utilization) public pure returns (uint256) {
        return BASE_RATE + ((utilization * MULTIPLIER) / 10000);
    }

    /**
     * @notice kink interest rate model (compound-style)
     * @param utilization utilization rate in basis points
     * @return interest rate in basis points
     */
    function getKinkRate(uint256 utilization) public pure returns (uint256) {
        if (utilization <= KINK) {
            return BASE_RATE + ((utilization * MULTIPLIER) / 10000);
        } else {
            uint256 normalRate = BASE_RATE + ((KINK * MULTIPLIER) / 10000);
            uint256 excessUtil = utilization - KINK;
            return normalRate + ((excessUtil * JUMP_MULTIPLIER) / 10000);
        }
    }

    /**
     * @notice exponential interest rate model
     * @param utilization utilization rate in basis points
     * @return interest rate in basis points
     */
    function getExponentialRate(uint256 utilization) public pure returns (uint256) {
        // using a simple square function for demonstration
        // in production, you might want to use a more sophisticated exponential function
        return BASE_RATE + ((utilization * utilization * MULTIPLIER) / 100000000);
    }

    /**
     * @notice get interest rate based on current model
     * @param _borrowAmount total amount borrowed
     * @param _totalSupply total amount supplied
     * @return interest rate in basis points
     */
    function getInterestRate(uint256 _borrowAmount, uint256 _totalSupply) public returns (uint256) {
        uint256 utilization = calculateUtilization(_borrowAmount, _totalSupply);
        uint256 rate;

        if (currentModel == ModelType.Linear) {
            rate = getLinearRate(utilization);
        } else if (currentModel == ModelType.Kink) {
            rate = getKinkRate(utilization);
        } else {
            rate = getExponentialRate(utilization);
        }

        emit InterestRateCalculated(utilization, rate);
        return rate;
    }

    /**
     * @notice change the current interest rate model
     * @param _newModel the new model type to use
     */
    function setModel(ModelType _newModel) external {
        currentModel = _newModel;
        emit ModelChanged(_newModel);
    }
}
