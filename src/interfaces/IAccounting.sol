// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IAccounting {
    /// @notice Get bond curve ID for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Bond curve ID
    function getBondCurveId(uint256 nodeOperatorId) external view returns (uint256);
}
