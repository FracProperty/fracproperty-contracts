// SPDX-License-Identifier: MIT
pragma solidity  0.8.3;

/**
 * Interface for Timelock Contract
 * Below are the functions used by the multisig contract
 * 
 */
interface TimeLockController 
{
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;

    function getMinDelay() external view returns (uint256 duration);
    
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32 hash);

    function isOperationReady(bytes32 id) external view returns (bool ready);
    
    function cancel(bytes32 id) external;
    function execute
    (
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;
}

pragma solidity 0.8.3;

//import only the used Gnosis files
import "./OwnerManager.sol";
import "./Executor.sol";
import "./Enum.sol";


/**
 * @dev Implementation of the Multisig Contract.
 * 
 * This contract uses the functionalities provided by Gnosis contracts(OwnerManager, Executor) for Multisig.
*/

contract FracMultisig  is OwnerManager, Executor{



/**
 * @dev Structure for holding information related to the transaction to be approved.
 *
 * txDesc: Transaction description.
 * txNote: A note that could be needed to highlighted for a transaction.
 * txTo  : The address of the contract that has the transaction to be executed. 
 * relatedTo: The address of a wallet that could be related to the transaction (eg: admin wallet address in case the transaction was adding or removing an admin)
 * txStatus : Status of the transaction ["A": approved, "P": pending, "C": cancelled].
 * approvals: Number of approvals the transaction has got
 * approvedBy: array of addresses of the owners that have approved the transaction.
*/

struct TxInfo {
        address addedBy; // total amount of given rewards to the user as a referral.
        string txDesc;
        string txNote;
        address txTo;
        address relatedTo;
        string txStatus;
        uint256 approvals;
        address[] approvedBy;
    }

uint256 private nonce;
bytes32 private currentTxHash;
mapping (address => mapping(uint256 => bool)) private txApproved;
mapping (uint256 => uint256) private txApprovals;
mapping (uint256 => TxInfo) private txInfo; 
bool private nothingToApprove;
TimeLockController public timeLockController;

/**
 * @dev Initializes the contract with primary settings.
*/
  constructor() 
  {
      address[] memory initOwners = new address[](1);
      initOwners[0] = msg.sender;
      setupOwners(initOwners,1);
      nothingToApprove = true;
      nonce = 0;
  }


    /**
     * @dev Emitted when a transaction is added
     */
    event AddTransactionAndApprove(address _by, address _to, string _txDesc, address _txRelatedTo);

    /**
     * @dev Emitted when a transaction is approved by an owner
     */
    event ApproveTransaction(address _by, address _to, string _txDesc, address _txRelatedTo);

    /**
     * @dev Emitted when a transaction is cancelled
     */
    event CancelCurrentTransaction(address _by, address _to, string _txDesc, address _txRelatedTo);

    /**
     * @dev Emitted when a transaction is executed
     */
    event ExecuteTransaction(address _by, address _to, string _txDesc, address _txRelatedTo);


    /**
     * @dev Returns the ID of current transaction.
     */

    function currentTransactionID() external view returns(uint256 _id)
    {
        return nonce;
    }

    /**
     * @dev Returns hash needed for validation check when a transaction is to be processed.
     */
    function checkHash(address _owner, bytes memory  _data, address to) private view returns(bytes32 _hash)
    {
        return keccak256(abi.encode(_owner,_data,nonce,to));
    }


    /**
     * @dev add new transaction to be approved.
     *
     * 
     * Emits an {AddTransactionAndApprove} event indicating that a transaction is added.
     * Emits an {ExecuteTransaction} event indicating that an internal multisig function is executed.
     *
     * @param _data the ABI encoding of the function to be executed
     * @param _to the address of the contract that contains the function to be executed
     * @param _txDesc the description of the transaction (eg: addAdmin, removeAdmin,...etc)
     * @param _txNote additional information that a transaction might have
     * @param _txRelatedTo The address of a wallet that could be related to the transaction
     * 
     */

    function addTransactionAndApprove(bytes calldata _data, address _to, string memory _txDesc, string memory _txNote, address _txRelatedTo) external payable onlyOwner returns(uint256)
    {
        require(nothingToApprove, "pending transaction is still waiting for approval");
        bytes32 txHash = checkHash(msg.sender,_data,_to);

        currentTxHash=txHash;
        txApproved[msg.sender][nonce] = true;

        TxInfo storage _tx =  txInfo[nonce];

        _tx.addedBy = msg.sender; 
        _tx.txDesc = _txDesc;
        _tx.txNote = _txNote;
        _tx.txTo = _to;
        _tx.relatedTo = _txRelatedTo;
        _tx.txStatus = "P";
        _tx.approvedBy.push(msg.sender);
        _tx.approvals = _tx.approvals+1;

        txApprovals[nonce] = txApprovals[nonce]+1;
        nothingToApprove = false;

        /* 
        if only 1 approval is required for a transaction to be executed at the time of adding a new transaction, then 
        it sould be executed
        */
        if(threshold==1)
        {
            //Here we are checking if the targeted contract is the multisig itself
            if (_to == address(this))
            {
                if (execute(_to, msg.value, _data, Enum.Operation.Call, gasleft()))
                {
                    _tx.txStatus = "E";
                    emit ExecuteTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
                }
                else
                {
                    _tx.txStatus = "F";
                }
                nonce = nonce+1;
                nothingToApprove = true;
            }
            else
            {
                // below value of predecessor parameter is used by the schedule function of openzepplin timelock contract
                // and we will set its value to bytes32(0) because we don't have related transactions 
                bytes32 predecessor = 0x0000000000000000000000000000000000000000000000000000000000000000;  
                timeLockController.schedule(_to, msg.value, _data, predecessor, keccak256(abi.encode(nonce)), timeLockController.getMinDelay());

                _tx.txStatus = "A";
            }
        }

        emit AddTransactionAndApprove(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
        return nonce;
    }

    /**
     * @dev Check if any pending transaction is waiting to be approved by the owner
     */
    function pendingForOwnerApproval(address _owner) external view returns(bool)
    {
        return (!nothingToApprove && (txApproved[_owner][nonce] == false));
    }

    /**
     * @dev Check if any transaction is still pending
     */
    function isInProcessOfApproval() external view returns(bool)
    {
        return !nothingToApprove;
    }
    
    /**
     * @dev approve the pending transaction.
     *
     * 
     * Emits an {ApproveTransaction} event indicating that the pending transaction is approved by an owner.
     *
     * @param _data the ABI encoding of the function to be executed
     * @param _to the address of the contract that contains the function to be executed
     * 
     */

    function approveTransaction(bytes calldata _data, address _to) external payable onlyOwner returns(uint256)
    {
        require(!nothingToApprove, "no pending transaction is waiting for approval");

        //1 means approved
        //2 means approved & scheduled
        //3 means approved & executed sucessfully
        //4 means approved & executed failed
        uint256 returnedVal=1;

        TxInfo storage _tx =  txInfo[nonce];
        bytes32 txHash = checkHash(_tx.addedBy,_data,_to);

        require((currentTxHash==txHash), "This transaction is not the current transaction for approval!");
        require((txApproved[msg.sender][nonce] == false), "The transaction has already been approved by the owner!");


        txApproved[msg.sender][nonce] = true;
        txApprovals[nonce] = txApprovals[nonce]+1;

        _tx.approvals = _tx.approvals+1;
        _tx.approvedBy.push(msg.sender);


        // if the number of approvals reached the threshold, then execute the function.
        if(txApprovals[nonce]>=threshold)
        {
            // we have reached the minimum required approvals, we need to schudle the transaction using the timelock contract from openzepplin

            //Here we are checking if the targeted contract is the multisig itself
            if (_to == address(this))
            {
                if (execute(_to, msg.value, _data, Enum.Operation.Call, gasleft()))
                {
                    _tx.txStatus = "E";
                    emit ExecuteTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
                    returnedVal = 3;
                }
                else
                {
                    _tx.txStatus = "F";
                    returnedVal = 4;
                }
                nonce = nonce+1;
                nothingToApprove = true;
            }
            else
            {
                // below value of predecessor parameter is used by the schedule function of openzepplin timelock contract
                // and we will set its value to bytes32(0) because we don't have related transactions 
                bytes32 predecessor = 0x0000000000000000000000000000000000000000000000000000000000000000;  
                timeLockController.schedule(_to, msg.value, _data, predecessor, keccak256(abi.encode(nonce)), timeLockController.getMinDelay());
            
                _tx.txStatus = "A";
                returnedVal = 2;
            }
        }

        emit ApproveTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
        return returnedVal;
    }


    /**
     * @dev cancel the current transaction if it's not executed yet.
     *
     * @param _data the ABI encoding of the function to be executed
     * 
     * Emits a {CancelCurrentTransaction} event indicating that the pending transaction is cancelled.
     * 
     */
    function cancelCurrentTransaction(bytes calldata _data) external payable onlyOwner returns(bool _success)
    {
        require(!nothingToApprove, "no pending transaction is waiting for approval/execution");

        TxInfo storage _tx =  txInfo[nonce];

        //Here we are checking if the targeted contract is the multisig itself
        if (_tx.txTo != address(this) && keccak256(abi.encode(_tx.txStatus))==keccak256(abi.encode("A")))
        {
            //Cancel the transaction in the timelock contract
            // below value of predecessor parameter is used by the schedule function of openzepplin timelock contract
            // and we will set its value to bytes32(0) because we don't have related transactions 
            bytes32 predecessor = 0x0000000000000000000000000000000000000000000000000000000000000000;  
            bytes32 operationHash = timeLockController.hashOperation(_tx.txTo, msg.value, _data, predecessor, keccak256(abi.encode(nonce)));
            timeLockController.cancel(operationHash);
        }
        
        //Cancel the transaction in the multisig side 
        _tx.txStatus = "C";
        nonce=nonce+1; 

        //We are ready to process another transaction
        nothingToApprove = true;

        emit CancelCurrentTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
        return nothingToApprove;
    }

     /**
     * @dev execute the approved transaction if it's ready on the timelock contract side.
     *
     * 
     * Emits an {ExecuteTransaction} event indicating that the pending transaction is executed by an owner.
     *
     * @param _data the ABI encoding of the function to be executed
     * 
     */

    function executeTransaction(bytes calldata _data) external payable onlyOwner returns(bool _success)
    {
        require(!nothingToApprove, "no pending transaction is waiting for execution");
        TxInfo storage _tx =  txInfo[nonce];
        
        //Check if the trasacation is approved
        require(keccak256(abi.encode(_tx.txStatus))==keccak256(abi.encode("A")), "the transaction is not approved yet");

        //Check if the transaction is ready to execute
        // below value of predecessor parameter is used by the schedule function of openzepplin timelock contract
        // and we will set its value to bytes32(0) because we don't have related transactions 
        bytes32 predecessor = 0x0000000000000000000000000000000000000000000000000000000000000000;  
        bytes32 operationHash = timeLockController.hashOperation(_tx.txTo, msg.value, _data, predecessor, keccak256(abi.encode(nonce)));
        require(timeLockController.isOperationReady(operationHash), "the transaction requires more time to be executable");
        
        
        //Execcute the transaction
        timeLockController.execute(_tx.txTo, msg.value, _data, predecessor, keccak256(abi.encode(nonce)));

        //Cancel the transaction in the multisig side 
        _tx.txStatus = "E";
        nonce=nonce+1; 

        //We are ready to precess another transaction
        nothingToApprove = true;

        emit ExecuteTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
        return nothingToApprove;
    }

    /**
     * @dev returns information about a transaction
     */
    function getTxInfo(uint256 _txId) external view onlyOwner returns(TxInfo memory _txInfo)
    {
        TxInfo storage _tx = txInfo[_txId];
        return _tx;
    }

    /*
    * @dev Allows to update the address of the TimeLockController
    * @param _timelockContraller New TimeLockContraller address
    */
    function setTimelockContract(TimeLockController _timelockContraller) public authorized
    {
        timeLockController = _timelockContraller;
    }
}
