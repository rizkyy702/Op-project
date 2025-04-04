// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";
import {CrossDomainMessageLib} from "@interop-lib/libraries/CrossDomainMessageLib.sol";
import {IL2ToL2CrossDomainMessenger} from "@interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol";
import {ISuperchainWETH} from "@interop-lib/interfaces/ISuperchainWETH.sol";

error IncorrectValue();

contract RemoteMultisend {
    struct Send {
        address to;
        uint256 amount;
    }

    ISuperchainWETH internal immutable superchainWeth = ISuperchainWETH(payable(PredeployAddresses.SUPERCHAIN_WETH));
    IL2ToL2CrossDomainMessenger internal immutable l2ToL2CrossDomainMessenger =
        IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    receive() external payable {}

    function send(uint256 _destinationChainId, Send[] calldata _sends) public payable returns (bytes32) {
        uint256 totalAmount;
        for (uint256 i; i < _sends.length; i++) {
            totalAmount += _sends[i].amount;
        }

        if (msg.value != totalAmount) revert IncorrectValue();

        bytes32 sendWethMsgHash = superchainWeth.sendETH{value: totalAmount}(address(this), _destinationChainId);

        return l2ToL2CrossDomainMessenger.sendMessage(
            _destinationChainId, address(this), abi.encodeCall(this.relay, (sendWethMsgHash, _sends))
        );
    }

    function relay(bytes32 _sendWethMsgHash, Send[] calldata _sends) public {
        CrossDomainMessageLib.requireCrossDomainCallback();
        // CrossDomainMessageLib.requireMessageSuccess uses a special error signature that the
        // auto-relayer performs special handling on. The auto-relayer parses the _sendWethMsgHash
        // and waits for the _sendWethMsgHash to be relayed before relaying this message.
        CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);

        for (uint256 i; i < _sends.length; i++) {
            address to = _sends[i].to;
            // use .call for example purpose, but not recommended in production.
            (bool success,) = to.call{value: _sends[i].amount}("");
            require(success, "ETH transfer failed");
        }
    }
}
