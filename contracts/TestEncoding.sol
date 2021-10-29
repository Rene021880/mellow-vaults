// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultGovernance.sol";
import "./interfaces/IVaultRegistry.sol";
import "hardhat/console.sol";


contract TestEncoding {
    IProtocolGovernance.Params private data;
    address addr;

    function setDataCalldata(bytes calldata tempData) public {
        data = abi.decode(tempData, (IProtocolGovernance.Params));
    }

    function setDataMemory(bytes memory tempData) public {
        data = abi.decode(tempData, (IProtocolGovernance.Params));
    }

    function getData() public view returns(IProtocolGovernance.Params memory) {
        return data;
    }

    function setAddress(bytes calldata _addr) public {
        addr = abi.decode(_addr, (address));
        console.log(addr);
    }

    function getAddress() public view returns(address) {
        return addr;
    }

}
