pragma solidity ^0.4.15;
import './interfaces/IRewardDAO.sol';

import './interfaces/IKnownTokens.sol';

import './BNK.sol';
import './Balances.sol';
import './SafeMath.sol';
import './KnownTokens.sol';

import './bancor_contracts/BancorChanger.sol';
import './bancor_contracts/BancorFormula.sol';
import './bancor_contracts/EtherToken.sol';
import './bancor_contracts/interfaces/IERC20Token.sol';

/**
    RewardDAO autonomous interest yielding solution to cryptocurrency banking.
 */
contract RewardDAO is IRewardDAO {
    using SafeMath for uint;

    struct Vault {
        address balances;
        uint unclaimeDAO;
        uint totalBNK;
        uint withdrawalFee;
    }

    uint constant FEE_MULTIPLIER = 100;
    uint constant MAX_USERS = 1000;

    BNK bnkToken;                // TODO: Remove this, since all the transfers will be within the Balances
    ITokenChanger tokenChanger;  // TODO make this of type IBancorChanger to facilitate future upgrades
    IKnownTokens knownTokens;

    mapping(address => Vault) addressToSCMap;
    address[] users;

    event SavingsContractCreated(address indexed savingsContractAddress);
    event TokensClaimed();
    event Log(uint amount);

    /**
        @dev constructor

        @param _tokenChanger    Address of a deployed TokenChanger contract (i.e. BancorChanger)
        @param _bnkToken       Address of the account from where bnkTokens are being issued.
        @param _knownTokens     Address of a deployed IKnownTokens contract (i.e. KnownTokens).
    */
    function RewardDAO(ITokenChanger _tokenChanger, IKnownTokens _knownTokens, BNK _bnkToken, EtherToken _etherToken) {
        tokenChanger = _tokenChanger;
        bnkToken    = _bnkToken;
        knownTokens  = _knownTokens;

        knownTokens.addToken(address(_bnkToken));
        knownTokens.addToken(address(_etherToken));
    }

    /**
        @dev deploys vault onto blockchain, creating associated balance for vault
    */
    function deploySavingsContract()
        public
    {
        assert(users.length < MAX_USERS);
        assert(!search(msg.sender, users));
        users.push(msg.sender);

        // Creates the SavingsContract.
        Balances b = new Balances(address(this), address(bnkToken), msg.sender);
        addressToSCMap[msg.sender].balances = address(b);
        addressToSCMap[msg.sender].unclaimeDAO = 0;
        addressToSCMap[msg.sender].withdrawalFee = 0;

        SavingsContractCreated(msg.sender);
    }

    /**
        @dev claim your BNK held by the RewardDAO by transferring funds in the the save to balance
    */
    function claim()
        public
    {
        require(search(msg.sender, users));

        var sc = addressToSCMap[msg.sender];
        assert(sc.unclaimeDAO > 0);

        var claimAmount = sc.unclaimeDAO;
        delete sc.unclaimeDAO;

        var oldTotalBNK = sc.totalBNK;
        sc.totalBNK = oldTotalBNK.add(claimAmount);

        bnkToken.transfer(sc.balances, claimAmount);

        TokensClaimed();
    }

    /**
        @dev user facing deposit function
        TODO: UPDATE THE WITHDRAWAL FEE.

         @param _token    Address of the ERC20 token being deposited, or the ether wrapper
         @param _amount   Amount of said token being deposited into save
    */
    function deposit(address _token, uint _amount)
        public
    {
        // Ensure that the RewardDAO is aware of the token
        // being sent as a deposit.
        require(knownTokens.containsToken(_token));

        // Require that the user is registered with the RewardDAO.
        require(search(msg.sender, users));
        var sc = addressToSCMap[msg.sender];

        IERC20Token token = IERC20Token(_token);
        require(_amount > 0);
        assert(token.balanceOf(msg.sender) > _amount);

        Balances bal = Balances(sc.balances);
        var oldBalance = bal.queryBalance(msg.sender);
        var newBalance = oldBalance.add(_amount);

        var oldFee = sc.withdrawalFee;
        var newFee = calcFee(sc, newBalance, _token);

        // TODO: Double check this
        // set the sc fee to be maximum of the previous and updated fee
        if (newFee < oldFee) { sc.withdrawalFee = oldFee; }
        else                 { sc.withdrawalFee = newFee; }

        bal.deposit(msg.sender, _token, _amount);
    }

    /**
        @dev withdraws entirety of the vault into user's balance and destroys the vault
        TODO: Implement snapshots on every block so we can keep track of people's overall stake in the system.
    */
    function withdraw()
        public
    {
        require(search(msg.sender, users));

        var sc = addressToSCMap[msg.sender];
        var bal = Balances(sc.balances);

        // require the withdrawer to pay some amount of money before transferring money to account
        assert(sc.unclaimeDAO == 0);
        assert(sc.withdrawalFee != 0);
        bnkToken.transferFrom(msg.sender, address(this), sc.withdrawalFee);

        // transfer all the tokens associated with the balance to the user account

        // TODO: Put the below back in
        /* address[] knownTokensList = knownTokens.getKnownTokensList();
        for (uint i = 0; i < knownTokensList.length; ++i) {
            bal.withdraw(msg.sender, knownTokensList[i]);
        } */

        // resets all the defaults in case anything goes wrong in deletion
        addressToSCMap[msg.sender].balances      = 0x0;
        addressToSCMap[msg.sender].unclaimeDAO   = 0;
        addressToSCMap[msg.sender].withdrawalFee = 0;
        delete addressToSCMap[msg.sender];
    }

    /** ----------------------------------------------------------------------------
        *                       Private helper functions                             *
        ---------------------------------------------------------------------------- */

    /**
        @dev arbitrates the deposits into Balances

        @param  _amount      Amount (in bnkTokens) being deposited into the vault
        @return boolean success of the deposit
    */
    function onDeposit(uint _amount) returns (bool) {
        assert(true); // TODO
        Log(_amount);
        return true;
    }

    /**
        @dev Calculates the new withdrawal fee everytime a user submits a deposit of token.
             Private function in which all the variable have already been checked for accuracy in the calling
             public-facing function.

        @param _vault The address for the vault to be determined.
        @param _newBalance The new balance of token to calculate with.
        @param _token The address of the token which was deposited
        @return The new withdrawal fee to be paid.

    function calcFee(Vault _vault, uint _newBalance, address _token)
        private constant returns (uint)
    {
        uint runningTotal;
        var token = IERC20Token(_token);

        for (uint i = 0; i < knownTokens.length; ++i) {
            if ((knownTokens[i] == _token) &&
                (token == etherToken))
            {
                runningTotal.add(etherToken.balanceOf(_vault.balances));
            } else if ((knownTokens[i] == _token) &&
                       (token == bnkToken))
            {
                // TODO query bancorchanger
                var etherRepresentationOfbnkTokenHeld =
                        bancorChanger.getReturn(bnkToken, etherToken, _newBalance);
                runningTotal.add(
                    etherRepresentationOfbnkTokenHeld
                );
            } else {
                revert();
            }
        }

        return runningTotal;
    } */

    function calcFee(Vault _vault, uint _newBalance, address _token)
        private constant returns (uint) { return 1; }

    /**
        @dev Returns the amount of money in the save associated with the message sender in ETH

        @return Supply of ETH in the message sender's vault
    */
    // function getEthBalance()
    //     internal
    //     returns (uint)
    // {
    //     require(search(msg.sender, users));
    //     var v = addressToVaultMap[msg.sender];
    //     return bancorChanger.getReturn(bnkToken, etherToken, vault.unclaimeDAO);
    // }

    /**
        @dev Generic search function for finding an entry in address array.

        @param _query   Address being investigated
        @param _pool    The array we search in
        @return  boolean indicating if the entry was found (true) or not (false)
    */
    function search(address _query, address[] _pool)
        constant returns (bool)
    {
        for (uint i = 0; i < _pool.length; ++i) {
            if (_query == _pool[i]) {return true;}
        }
        return false;
    }
}
