pragma solidity ^0.4.15;
import './BNK.sol';
import './bancor_contracts/EtherToken.sol';
import './PriceDiscovery.sol';

import './interfaces/IPriceDiscovery.sol';
import './interfaces/IKnownTokens.sol';
import './bancor_contracts/interfaces/ITokenChanger.sol';

/**
    KnownTokens.sol is a shared data store contract between the RewardDAO
    and the user Balances. It allows for a central store for both
    contracts to call access from, and (TODO) opens an API to add
    more supported tokens to the TokenBnk protocol.
 */
contract KnownTokens is IKnownTokens {
    ITokenChanger tokenChanger;

    //    EG. priceDiscovery[token1][token2].exchangeRate();
    mapping(address => mapping(address => IPriceDiscovery)) priceDiscoveryMap;

    address[] public allKnownTokens;

    /**
        @dev constructor

        @param  _tokenChanger   Address of the token changer (i.e. Bancor changer)

    */
    function KnownTokens(ITokenChanger _tokenChanger) {
        tokenChanger = _tokenChanger;
    }

    /**
        @dev Given the address of two tokens, determines what the conversion is, i.e.
        how many of token1 are in a single token2

        @param  _fromToken   FROM token address (i.e. conversion source)
        @param  _toToken     TO   token address (i.e. conversion destination)

    */
    function recoverPrice(address _fromToken, address _toToken)
        public constant returns (uint)
    {
        //TODO: implement function
        assert(_fromToken != _toToken); // ensure not doing useless conversion to same token
        var res = priceDiscoveryMap[_fromToken][_toToken];
        return res.exchangeRate();
    }

    /**
        @dev constructor

        @param  _newTokenAddr      Address of the new token being added
    */
    function addToken(address _newTokenAddr)
        public
    {
        // TODO: NEEDS TO BE CHANGED DRASTICALLY
        IERC20Token newToken = IERC20Token(_newTokenAddr);
        for (uint i = 0; i < allKnownTokens.length; ++i) {
            IERC20Token knownToken = IERC20Token(allKnownTokens[i]);

            var fromNewToken = new PriceDiscovery(newToken, knownToken, tokenChanger);
            priceDiscoveryMap[_newTokenAddr][allKnownTokens[i]] = fromNewToken;

            var toNewToken = new PriceDiscovery(knownToken, newToken, tokenChanger);
            priceDiscoveryMap[allKnownTokens[i]][_newTokenAddr] = toNewToken;
        }

        allKnownTokens.push(_newTokenAddr);
    }

    /**
        @dev Generic search function for finding an entry in address array.

        @param _token   Address of the token of interest (to see whether registered)
        @return  boolean indicating if the token was previously registered (true) or not (false)
    */
    function containsToken(address _token)
        public constant returns (bool)
    {
        for (uint i = 0; i < allKnownTokens.length; ++i) {
            if (_token == allKnownTokens[i]) {return true;}
        }
        return false;
    }
}