// SPDX-License-Identifier: MIT

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
bool private nothingToApproveOrExecute;
string private constant txStatusApproved="A";
mapping(uint256 => uint256) public lockTime;
uint private lockTimePeriod;


/**
 * @dev Initializes the contract with primary settings.
*/
  constructor() {
      address[] memory initOwners = new address[](1);
      initOwners[0] = msg.sender;
      setupOwners(initOwners,1);
      nothingToApproveOrExecute = true;
      lockTimePeriod = 60;
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
     * @dev Emitted when a transaction is executed
     */
    event ExecuteTransaction(address _by, address _to, string _txDesc, address _txRelatedTo);

    /**
     * @dev Emitted when a transaction is cancelled
     */
    event CancelCurrentTransaction(address _by, address _to, string _txDesc, address _txRelatedTo);

    /**
     * @dev Emitted when a transaction is cancelled
     */
    event SetLocktimePeriod(address _by, uint256 _periodInMinutes);

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
     * @dev set lockTime period.
     *
     * 
     * Emits an {SetLocktimePeriod} event indicating that a locktime period has been changed.
     *
     * @param _periodInSeconds The new value for locktime in seconds.
     * 
     */
    
    function setLocktimePeriod(uint256 _periodInSeconds) external authorized returns(bool _success)
    {
        lockTimePeriod = _periodInSeconds;
        
        return true;
    }

    /**
     * @dev returns the current time lock period in seconds
     */

    function getLocktimePeriod() external view returns(uint256)
    {
        return lockTimePeriod;
    }

    /**
     * @dev add new transaction to be approved.
     *
     * 
     * Emits an {AddTransactionAndApprove} event indicating that a transaction is added.
     *
     * @param _data the ABI encoding of the function to be executed
     * @param _to the address of the contract that contains the function to be executed
     * @param _txDesc the description of the transaction (eg: addAdmin, removeAdmin,...etc)
     * @param _txNote additional information that a transaction might have
     * @param _txRelatedTo The address of a wallet that could be related to the transaction
     * 
     */
    
    function addTransactionAndApprove(bytes calldata _data, address _to, string memory _txDesc, string memory _txNote, address _txRelatedTo) external payable onlyOwner returns(string memory)
    {
        require(nothingToApproveOrExecute, "pending transaction is still waiting for approval or execution!");
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
		nothingToApproveOrExecute = false;
    
        /* 
        if only 1 approval is required for a transaction  at the time of adding a new transaction, then 
        it sould be approved
        */
        if(threshold==1)
        {
            _tx.txStatus = "A";
            lockTime[nonce]= block.timestamp + lockTimePeriod;
        }
        
		emit ApproveTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
		
		//Return the current transcation status
        return _tx.txStatus;
    }
    
    /**
     * @dev Check if any pending transaction is waiting to be approved by the owner
     */
    function pendingForOwnerApproval(address _owner) external view returns(bool)
    {
        return (!nothingToApproveOrExecute && (txApproved[_owner][nonce] == false));
    }

    /**
     * @dev Check if any transaction is still pending
     */
    function isInProcessOfApproval() external view returns(bool)
    {
        return !nothingToApproveOrExecute;
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

    function approveTransaction(bytes calldata _data, address _to) external payable onlyOwner returns(string memory)
    {
        require(!nothingToApproveOrExecute, "no pending transaction is waiting for approval or execution");
        
        TxInfo storage _tx =  txInfo[nonce];
        bytes32 txHash = checkHash(_tx.addedBy,_data,_to);
        
        require((currentTxHash==txHash), "This transaction is not the current transaction for approval!");
        require((txApproved[msg.sender][nonce] == false), "The transaction has already been approved by the owner!");
        
		//Check if the transaction status is still pending, meaning to say we can add one another approval
        if (keccak256(abi.encode(_tx.txStatus))==keccak256(abi.encode("P")))
		{
			txApproved[msg.sender][nonce] = true;
			txApprovals[nonce] = txApprovals[nonce]+1;
			
			_tx.approvals = _tx.approvals+1;
			_tx.approvedBy.push(msg.sender);
			
			
			// if the number of approvals reached the threshold, then we chane the status to "A" means approved
			if(txApprovals[nonce]>=threshold)
			{
				_tx.txStatus = "A";
				lockTime[nonce]= block.timestamp + lockTimePeriod;
			}

			emit ApproveTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
		}
        
		//Return the current transcation status
        return _tx.txStatus;
    }


    /**
     * @dev cancel the pending transaction.
     *
     * 
     * Emits a {CancelCurrentTransaction} event indicating that the pending transaction is cancelled.
     * 
     */
    function cancelCurrentTransaction() external onlyOwner returns(uint256)
    {
        require(!nothingToApproveOrExecute, "no pending transaction is waiting for approval or execution");

        nothingToApproveOrExecute = true;
        TxInfo storage _tx =  txInfo[nonce];
		
		//Change the status to "C" which means cancelled
        _tx.txStatus = "C";
        
		//Incrase the nonce by one
        nonce=nonce+1; 
		
        emit CancelCurrentTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
        return nonce;
    }
    
    
    /**
     * @dev returns information about a transaction
     */
    function getTxInfo(uint256 _txId) external view onlyOwner returns(TxInfo memory _txInfo)
    {
        TxInfo storage _tx = txInfo[_txId];
        return _tx;
    }
    
    /**
     * @dev returns information about a lockTime
     */
    function getCurrentTimeInfo(uint _nonce) external view returns(uint256 _timeStamp, uint256 _lockTimePeriod,uint256 _lockTime)
    {
        return (block.timestamp,lockTimePeriod,lockTime[_nonce]);
        
    }
    


    /**
     * @dev execute the approved transaction.
     *
     * 
     * Emits an {ExecuteTransaction} event indicating that the pending transaction is executed by an owner.
     *
     * @param _data the ABI encoding of the function to be executed
     * @param _to the address of the contract that contains the function to be executed
     * 
     */

    function executeTransaction(bytes calldata _data, address _to) external payable onlyOwner returns(bool _success)
    {
        require(!nothingToApproveOrExecute, "no pending transaction is waiting for approval");
        TxInfo storage _tx =  txInfo[nonce];
        bytes32 txHash = checkHash(_tx.addedBy,_data,_to);

        require((currentTxHash==txHash), "This transaction is not the current transaction for approval or execution!");
        require((keccak256(abi.encode(_tx.txStatus))==keccak256(abi.encode(txStatusApproved))), "This transaction is not in 'Approved' stage!");
        require(block.timestamp >= lockTime[nonce], "lock time has not expired");
    
        bool ret;
		ret = execute(_to, msg.value, _data, Enum.Operation.Call, gasleft());
		
        if (ret==true)
        {
		    // change status to 'E': "executed"
		    _tx.txStatus = "E";
        }
        else
        {
            // change status to 'F': "failed"
		    _tx.txStatus = "F";
        }
		nothingToApproveOrExecute = true;
		nonce = nonce+1;

        emit ExecuteTransaction(msg.sender, _tx.txTo, _tx.txDesc, _tx.relatedTo);
        
        return ret;
    }
}
