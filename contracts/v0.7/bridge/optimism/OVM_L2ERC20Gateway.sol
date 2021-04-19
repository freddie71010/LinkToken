// SPDX-License-Identifier: MIT
pragma solidity >0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
import { IERC20Child } from "../token/IERC20Child.sol";
import { ERC677Receiver } from "../../../v0.6/token/ERC677Receiver.sol";

/* Library Imports */
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/* Contract Imports */
import { iOVM_L1TokenGateway } from "@eth-optimism/contracts/iOVM/bridge/tokens/iOVM_L1TokenGateway.sol";
import { Abs_L2DepositedToken } from "@eth-optimism/contracts/OVM/bridge/tokens/Abs_L2DepositedToken.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";
import { OpUnsafe } from "../utils/OpUnsafe.sol";
import { OVM_EOACodeHashSet } from "./OVM_EOACodeHashSet.sol";

/**
 * @title OVM_L2ERC20Gateway
 * @dev The L2 Deposited LinkToken is an token implementation which represents L1 assets deposited into L2.
 * This contract mints new tokens when it hears about deposits into the L1 token gateway.
 * This contract also burns the tokens intended for withdrawal, informing the L1 gateway to release L1 funds.
 *
 * Compiler used: optimistic-solc
 * Runtime target: OVM
 */
contract OVM_L2ERC20Gateway is ERC677Receiver, OpUnsafe, OVM_EOACodeHashSet, Initializable, Abs_L2DepositedToken {
  // Bridged L2 token
  IERC20Child public s_l2ERC20;

  /// @dev This contract lives behind a proxy, so the constructor parameters will go unused.
  constructor()
    Abs_L2DepositedToken(
      address(0) // _l2CrossDomainMessenger
    )
    public
  {}

  /**
   * @param l1ERC20Gateway L1 Gateway address on the chain being withdrawn into
   * @param l2Messenger Cross-domain messenger used by this contract.
   * @param l2ERC20 L2 ERC20 address this contract deposits for
   */
   // TODO: What to do with DevEx here? (overloaded fn)
  function init_2(
    address l1ERC20Gateway,
    address l2Messenger,
    address l2ERC20
  )
    public
    initializer()
  {
    require(l1ERC20Gateway != address(0), "Init to zero address");
    require(l2Messenger != address(0), "Init to zero address");
    require(l2ERC20 != address(0), "Init to zero address");

    s_l2ERC20 = IERC20Child(l2ERC20);
    // Init parent contracts
    super.init(iOVM_L1TokenGateway(l1ERC20Gateway));
    messenger = l2Messenger;
  }

  /**
   * @dev Hook on successful token transfer that initializes withdrawal
   * @notice Avoids two step approve/transferFrom, and only works for EOA.
   * @inheritdoc ERC677Receiver
   */
  function onTokenTransfer(
    address _sender,
    uint _value,
    bytes memory /* _data */
  )
    external
    override
  {
    require(msg.sender == address(s_l2ERC20), "onTokenTransfer sender not valid");
    _initiateWithdrawal(_sender, _value);
  }

  /**
   * @dev initiate a withdraw of some token to a recipient's account on L1
   * WARNING: This is a potentially unsafe operation that could end up with lost tokens,
   * if tokens are sent to a contract. Be careful!
   *
   * @param _to L1 adress to credit the withdrawal to
   * @param _amount Amount of the token to withdraw
   */
  function withdrawToUnsafe(
    address _to,
    uint _amount
  )
    external
    unsafe()
  {
    _initiateWithdrawal(_to, _amount);
  }

  /**
   * @dev When a withdrawal is initiated, we burn the funds to prevent subsequent L2 usage.
   * @inheritdoc Abs_L2DepositedToken
   */
  function _handleInitiateWithdrawal(
    address _to,
    uint _amount
  )
    internal
    override
    onlyInitialized()
  {
    // Unless explicitly unsafe op, stop withdrawals to contracts (avoid accidentally lost tokens)
    require(_isUnsafe() || !Address.isContract(_to) || _isEOAContract(_to), "Unsafe withdraw to contract");

    // Check if funds already transfered via trasferAndCall (skipping)
    if (msg.sender != address(s_l2ERC20)) {
      // Take the newly deposited funds (must be approved)
      s_l2ERC20.transferFrom(
        msg.sender,
        address(this),
        _amount
      );
    }

    // And withdraw them to L1
    s_l2ERC20.withdraw(_amount);
  }

  /**
   * @dev When a deposit is finalized, we credit the account on L2 with the same amount of tokens.
   * @inheritdoc Abs_L2DepositedToken
   */
  function _handleFinalizeDeposit(
    address _to,
    uint _amount
  )
    internal
    override
    onlyInitialized()
  {
    s_l2ERC20.deposit(_to, _amount);
  }
}
