pragma solidity ^0.4.11;

import "../token/ERC23.sol";
import "../token/MiniMeToken.sol";

/**
 * @title TokenBank 
 * @author Ricardo Guilherme Schmidt 
 * Abstract contract for deposit and withdraw of ETH and ERC20/23 Tokens, with MiniMe token support.
 **/
contract TokenBank is ERC23Receiver, ApproveAndCallFallBack {
    
    event Withdrawn(address token, address reciever, uint amount);
    event Deposited(address token, address sender, uint value);
    
    mapping (address => mapping (address => uint)) public deposits;
    mapping (address => uint) public tokenBalances;
    address[] public tokens;

    uint public nonce;
    
    /**
     * @notice deposit ether in bank
     * @param _data might be used by child implementations
     **/
    function depositEther(bytes _data) payable {
        _deposited(msg.sender, msg.value, 0x0, _data);
    }
    
    /**
     * @notice deposit a ERC20 token. The amount of deposit is the allowance set to this contract.
     * @param _token the token contract address
     * @param _data might be used by child implementations
     **/ 
     function depositToken(address _token, bytes _data){
         address sender = msg.sender;
         uint amount = ERC20(_token).allowance(sender, this);
         deposit(sender, amount, _token, _data);
     }
     
     /**
     * @notice deposit a ERC20 token. The amount of deposit is the allowance set to this contract.
     * @param _token the token contract address
     * @param _data might be used by child implementations
     **/ 
    function deposit(address _from, uint256 _amount, address _token, bytes _data) {
        if(_from == address(this)) return;
        uint _nonce = nonce;
        ERC20 token = ERC20(_token);
        if(!token.transferFrom(_from, this, _amount)) throw;
        if(nonce == _nonce){ //ERC23 not executed _deposited tokenFallback by
            _deposited(_from, _amount, _token, _data);
        }
    }

    /**
     * @notice watches for balance in a token contract
     * @param _tokenAddr the token contract address
     **/   
    function watch(address _tokenAddr) {
        uint oldBal = tokenBalances[_tokenAddr];
        uint newBal = ERC20(_tokenAddr).balanceOf(this);
        if(newBal > oldBal){
            _deposited(0x0,newBal-oldBal,_tokenAddr,new bytes(0));
        }
    }
    
    /**
     * @notice refunds a deposit.
     * @param _token the token you want to refund
     **/   
    function refund(address _token) returns (bool) {
        address _sender = msg.sender;
        _withdraw(_token, _sender, deposits[_sender][_token], _sender);
        return true;
    }

    /**
     * @notice ERC23 Token fallback
     * @param _from address incoming token
     * @param _amount incoming amount
     **/    
    function tokenFallback(address _from, uint _amount, bytes _data) {
        _deposited(_from, _amount, msg.sender, _data);
    }
    
    /** 
     * @notice Called MiniMeToken approvesAndCall to this contract, calls deposit.
     * @param _from address incoming token
     * @param _amount incoming amount
     * @param _token the token contract address
     * @param _data (might be used by child classes)
     */ 
    function receiveApproval(address _from, uint256 _amount, address _token, bytes _data){
        deposit(_from, _amount, _token, _data);
    }
    
  
    /**
     * @dev register the deposit to refundings
     **/
    function _deposited(address _sender, uint _amount, address _tokenAddr, bytes _data)
     internal {
        Deposited(_tokenAddr, _sender, _amount);
        nonce++;
        if(_tokenAddr != 0x0){
            if(tokenBalances[_tokenAddr] == 0){
                tokens.push(_tokenAddr);  
                tokenBalances[_tokenAddr] = ERC20(_tokenAddr).balanceOf(this);
            }else{
                tokenBalances[_tokenAddr] += _amount;
            }
        }
        deposits[_sender][_tokenAddr] += _amount;
    }
    
    
    /**
     * @dev withdraw token amount to dest
     **/
    function _withdraw(address _tokenAddr, address _dest, uint _amount, address _consumer)
     internal returns (bool){
        Withdrawn(_tokenAddr, _dest, _amount);
        if(_consumer != 0x0) {
            require(deposits[_consumer][_tokenAddr] >= _amount);
            deposits[_consumer][_tokenAddr] -= _amount;
        }
        if(_tokenAddr == 0x0){ 
            _dest.transfer(_amount);
            return true;
        } else {
            tokenBalances[_tokenAddr] -= _amount;
            ERC20 token = ERC20(_tokenAddr);
            token.approve(this, 0); 
            if(token.approve(this, _amount)){
                return token.transferFrom(this, _dest, _amount);
            }
        }
    }

}
