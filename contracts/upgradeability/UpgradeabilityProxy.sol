pragma solidity ^0.4.24;

import './Proxy.sol';
import '../utils/Address.sol';

/**
 * @title UpgradeabilityProxy
 *
 * @dev This contract implements a proxy that allows to change the implementation address to which it will delegate.
 * Such a change is called an implementation upgrade.
 */
contract UpgradeabilityProxy is Proxy {
    /**
     * @dev Emitted when the implementation is upgraded.
     *
     * @param implementation Address of the new implementation.
     */
    event Upgraded(address implementation);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "speedProp0621.proxy.implementation", and is validated in the constructor.
     */
    bytes32 private constant IMPLEMENTATION_SLOT = 0x43f18ae19f743138a282f721d6d3302f79cf3dd6b85c8ebf432f3770f179e9f4;

    /**
     * @dev Contract constructor.
     *
     * @param _implementation Address of the initial implementation.
     */
    constructor(address _implementation) public {
        assert(IMPLEMENTATION_SLOT == keccak256("speedProp0621.proxy.implementation"));

        _setImplementation(_implementation);
    }

    /**
     * @dev Returns the current implementation.
     *
     * @return Address of the current implementation
     */
    function _implementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    /**
     * @dev Upgrades the proxy to a new implementation.
     *
     * @param newImplementation Address of the new implementation.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Sets the implementation address of the proxy.
     *
     * @param newImplementation Address of the new implementation.
     */
    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "Cannot set a proxy implementation to a non-contract address");

        bytes32 slot = IMPLEMENTATION_SLOT;

        assembly {
            sstore(slot, newImplementation)
        }
    }
}
