pragma solidity >=0.4.23;

import {DSDelegateToken} from "./delegate.sol";
import {DSToken} from "./token.sol";

contract DSTokenFactory {
    event LogMake(address indexed owner, address token);

    function make(
        string memory symbol, string memory name
    ) public returns (DSToken result) {
        result = new DSToken(name, symbol);
        result.setOwner(msg.sender);
        emit LogMake(msg.sender, address(result));
    }
}

contract DSDelegateTokenFactory {
    event LogMake(address indexed owner, address token);

    function make(
        string memory symbol, string memory name
    ) public returns (DSDelegateToken result) {
        result = new DSDelegateToken(name, symbol);
        result.setOwner(msg.sender);
        emit LogMake(msg.sender, address(result));
    }
}
