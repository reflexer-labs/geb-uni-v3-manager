/// delegate.t.sol -- test for delegate.sol

// Copyright (C) 2015, 2016, 2017  DappHub, LLC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.4.23;

import "ds-test/test.sol";

import "../delegate.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
}

contract TokenUser {
    DSDelegateToken  token;

    constructor(DSDelegateToken token_) public {
        token = token_;
    }

    function doTransferFrom(address from, address to, uint amount)
        public
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(address to, uint amount)
        public
        returns (bool)
    {
        return token.transfer(to, amount);
    }

    function doApprove(address recipient, uint amount)
        public
        returns (bool)
    {
        return token.approve(recipient, amount);
    }

    function doAllowance(address owner, address spender)
        public
        view
        returns (uint)
    {
        return token.allowance(owner, spender);
    }

    function doBalanceOf(address who) public view returns (uint) {
        return token.balanceOf(who);
    }

    function doApprove(address guy)
        public
        returns (bool)
    {
        return token.approve(guy);
    }
    function doPush(address who, uint amount) public {
        token.push(who, amount);
    }
    function doPull(address who, uint amount) public {
        token.pull(who, amount);
    }
    function doMove(address src, address dst, uint amount) public {
        token.move(src, dst, amount);
    }
    function doMint(uint wad) public {
        token.mint(wad);
    }
    function doBurn(uint wad) public {
        token.burn(wad);
    }
    function doMint(address guy, uint wad) public {
        token.mint(guy, wad);
    }
    function doBurn(address guy, uint wad) public {
        token.burn(guy, wad);
    }
    function doDelegate(address to) public {
        token.delegate(to);
    }
}

contract DSDelegateTokenTest is DSTest {
    uint constant initialBalance = 1000;

    DSDelegateToken token;
    address user1;
    address user2;
    address user3;
    address self;
    Hevm hevm;

    function setUp() public {
        token = createToken();
        token.mint(initialBalance);
        user1 = address(new TokenUser(token));
        user2 = address(new TokenUser(token));
        user3 = address(new TokenUser(token));
        self = address(this);

        // init hevm
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);
    }

    function createToken() internal returns (DSDelegateToken) {
        return new DSDelegateToken("TST", "TST");
    }

    function testSetupPrecondition() public {
        assertEq(token.balanceOf(self), initialBalance);
    }

    function testTransferCost() public logs_gas {
        token.transfer(address(0), 10);
    }

    function testAllowanceStartsAtZero() public logs_gas {
        assertEq(token.allowance(user1, user2), 0);
    }

    function testValidTransfers() public logs_gas {
        uint sentAmount = 250;
        emit log_named_address("token11111", address(token));
        token.transfer(user2, sentAmount);
        assertEq(token.balanceOf(user2), sentAmount);
        assertEq(token.balanceOf(self), initialBalance - sentAmount);
    }

    function testFailWrongAccountTransfers() public logs_gas {
        uint sentAmount = 250;
        token.transferFrom(user2, self, sentAmount);
    }

    function testFailInsufficientFundsTransfers() public logs_gas {
        uint sentAmount = 250;
        token.transfer(user1, initialBalance - sentAmount);
        token.transfer(user2, sentAmount + 1);
    }

    function testApproveSetsAllowance() public logs_gas {
        emit log_named_address("Test", self);
        emit log_named_address("Token", address(token));
        emit log_named_address("Me", self);
        emit log_named_address("User 2", user2);
        token.approve(user2, 25);
        assertEq(token.allowance(self, user2), 25);
    }

    function testChargesAmountApproved() public logs_gas {
        uint amountApproved = 20;
        token.approve(user2, amountApproved);
        assertTrue(TokenUser(user2).doTransferFrom(self, user2, amountApproved));
        assertEq(token.balanceOf(self), initialBalance - amountApproved);
    }

    function testFailTransferWithoutApproval() public logs_gas {
        token.transfer(user1, 50);
        token.transferFrom(user1, self, 1);
    }

    function testFailChargeMoreThanApproved() public logs_gas {
        token.transfer(user1, 50);
        TokenUser(user1).doApprove(self, 20);
        token.transferFrom(user1, self, 21);
    }
    function testTransferFromSelf() public {
        token.transferFrom(self, user1, 50);
        assertEq(token.balanceOf(user1), 50);
    }
    function testFailTransferFromSelfNonArbitrarySize() public {
        // you shouldn't be able to evade balance checks by transferring
        // to yourself
        token.transferFrom(self, self, token.balanceOf(self) + 1);
    }

    function testMint() public {
        uint mintAmount = 10;
        token.mint(mintAmount);
        assertEq(token.totalSupply(), initialBalance + mintAmount);
    }
    function testMintself() public {
        uint mintAmount = 10;
        token.mint(mintAmount);
        assertEq(token.balanceOf(self), initialBalance + mintAmount);
    }
    function testMintGuy() public {
        uint mintAmount = 10;
        token.mint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);
    }
    function testFailMintNoAuth() public {
        TokenUser(user1).doMint(10);
    }
    function testMintAuth() public {
        token.setOwner(user1);
        TokenUser(user1).doMint(10);
    }
    function testFailMintGuyNoAuth() public {
        TokenUser(user1).doMint(user2, 10);
    }
    function testMintGuyAuth() public {
        token.setOwner(user1);
        TokenUser(user1).doMint(user2, 10);
    }

    function testBurn() public {
        uint burnAmount = 10;
        token.burn(burnAmount);
        assertEq(token.totalSupply(), initialBalance - burnAmount);
    }
    function testBurnself() public {
        uint burnAmount = 10;
        token.burn(burnAmount);
        assertEq(token.balanceOf(self), initialBalance - burnAmount);
    }
    function testFailBurnGuyWithoutTrust() public {
        uint burnAmount = 10;
        token.push(user1, burnAmount);
        token.burn(user1, burnAmount);
    }
    function testBurnGuyWithTrust() public {
        uint burnAmount = 10;
        token.push(user1, burnAmount);
        assertEq(token.balanceOf(user1), burnAmount);

        TokenUser(user1).doApprove(self);
        token.burn(user1, burnAmount);
        assertEq(token.balanceOf(user1), 0);
    }
    function testFailBurnNoAuth() public {
        token.transfer(user1, 10);
        TokenUser(user1).doBurn(10);
    }
    function testBurnAuth() public {
        token.transfer(user1, 10);
        token.setOwner(user1);
        TokenUser(user1).doBurn(10);
    }
    function testFailBurnGuyNoAuth() public {
        token.transfer(user2, 10);
        TokenUser(user2).doApprove(user1);
        TokenUser(user1).doBurn(user2, 10);
    }
    function testBurnGuyAuth() public {
        token.transfer(user2, 10);
        token.setOwner(user1);
        TokenUser(user2).doApprove(user1);
        TokenUser(user1).doBurn(user2, 10);
    }


    function testFailTransferWhenStopped() public {
        token.stop();
        token.transfer(user1, 10);
    }
    function testFailTransferFromWhenStopped() public {
        token.stop();
        TokenUser(user1).doTransferFrom(self, user2, 10);
    }
    function testFailPushWhenStopped() public {
        token.stop();
        token.push(user1, 10);
    }
    function testFailPullWhenStopped() public {
        token.approve(user1);
        token.stop();
        TokenUser(user1).doPull(self, 10);
    }
    function testFailMoveWhenStopped() public {
        token.approve(user1);
        token.stop();
        token.move(self, user2, 10);
    }
    function testFailMintWhenStopped() public {
        token.stop();
        token.mint(10);
    }
    function testFailMintGuyWhenStopped() public {
        token.stop();
        token.mint(user1, 10);
    }
    function testFailBurnWhenStopped() public {
        token.stop();
        token.burn(10);
    }
    function testFailTrustWhenStopped() public {
        token.stop();
        token.approve(user1);
    }

    function testFailUntrustedTransferFrom() public {
        assertEq(token.allowance(self, user2), 0);
        TokenUser(user1).doTransferFrom(self, user2, 200);
    }
    function testTrusting() public {
        assertEq(token.allowance(self, user2), 0);
        token.approve(user2);
        assertEq(token.allowance(self, user2), uint(-1));
        token.approve(user2, 0);
        assertEq(token.allowance(self, user2), 0);
    }
    function testTrustedTransferFrom() public {
        token.approve(user1);
        TokenUser(user1).doTransferFrom(self, user2, 200);
        assertEq(token.balanceOf(user2), 200);
    }

    function testPush() public {
        assertEq(token.balanceOf(self), 1000);
        assertEq(token.balanceOf(user1), 0);
        token.push(user1, 1000);
        assertEq(token.balanceOf(self), 0);
        assertEq(token.balanceOf(user1), 1000);
        TokenUser(user1).doPush(user2, 200);
        assertEq(token.balanceOf(self), 0);
        assertEq(token.balanceOf(user1), 800);
        assertEq(token.balanceOf(user2), 200);
    }
    function testFailPullWithoutTrust() public {
        TokenUser(user1).doPull(self, 1000);
    }
    function testPullWithTrust() public {
        token.approve(user1);
        TokenUser(user1).doPull(self, 1000);
    }
    function testFailMoveWithoutTrust() public {
        TokenUser(user1).doMove(self, user2, 1000);
    }
    function testMoveWithTrust() public {
        token.approve(user1);
        TokenUser(user1).doMove(self, user2, 1000);
    }
    function testApproveWillModifyAllowance() public {
        assertEq(token.allowance(self, user1), 0);
        assertEq(token.balanceOf(user1), 0);
        token.approve(user1, 1000);
        assertEq(token.allowance(self, user1), 1000);
        TokenUser(user1).doPull(self, 500);
        assertEq(token.balanceOf(user1), 500);
        assertEq(token.allowance(self, user1), 500);
    }
    function testApproveWillNotModifyAllowance() public {
        assertEq(token.allowance(self, user1), 0);
        assertEq(token.balanceOf(user1), 0);
        token.approve(user1);
        assertEq(token.allowance(self, user1), uint(-1));
        TokenUser(user1).doPull(self, 1000);
        assertEq(token.balanceOf(user1), 1000);
        assertEq(token.allowance(self, user1), uint(-1));
    }

    function testFailTransferOnlyTrustedCaller() public {
        // only the entity actually trusted should be able to call
        // and move tokens.
        token.push(user1, 1);
        TokenUser(user1).doApprove(user2);
        token.transferFrom(user1, user2, 1);
    }

    // delegation tests
    // testing checkpoints
    function testCheckpoints() public {
        token.transfer(user1, 100); // user1 = delegator
        assertEq(uint256(token.numCheckpoints(user2)), 0);

        hevm.roll(1);

        TokenUser(user1).doDelegate(user2);
        assertEq(uint256(token.numCheckpoints(user2)), 1);

        hevm.roll(2);

        TokenUser(user1).doTransfer(user3, 10);
        assertEq(uint256(token.numCheckpoints(user2)), 2);

        hevm.roll(3);

        TokenUser(user1).doTransfer(user3, 10);
        assertEq(uint256(token.numCheckpoints(user2)), 3);

        hevm.roll(4);

        token.transfer(user1, 20);
        assertEq(uint256(token.numCheckpoints(user2)), 4);

        (uint blockNumber, uint votes) = token.checkpoints(user2, 0);
        assertEq(votes, 100);
        assertEq(blockNumber, 1);
        (blockNumber, votes) = token.checkpoints(user2, 1);
        assertEq(votes, 90);
        assertEq(blockNumber, 2);
        (blockNumber, votes) = token.checkpoints(user2, 2);
        assertEq(votes, 80);
        assertEq(blockNumber, 3);
        (blockNumber, votes) = token.checkpoints(user2, 3);
        assertEq(votes, 100);
        assertEq(blockNumber, 4);
    }


    // only one checkpoint per block
    function testOneCheckpointPerBlock() public {
        token.transfer(user1, 100); // user1 = delegator
        assertEq(uint256(token.numCheckpoints(user2)), 0);

        hevm.roll(1);

        TokenUser(user1).doDelegate(user2);
        TokenUser(user1).doTransfer(user3, 10);
        TokenUser(user1).doTransfer(user3, 10);
        assertEq(uint256(token.numCheckpoints(user2)), 1);

        hevm.roll(2);

        assertEq(uint256(token.numCheckpoints(user2)), 1);

        (uint blockNumber, uint votes) = token.checkpoints(user2, 0);
        assertEq(votes, 80);
        assertEq(blockNumber, 1);
        (blockNumber, votes) = token.checkpoints(user2, 1);
        assertEq(votes, 0);
        assertEq(blockNumber, 0);

        token.transfer(user1, 20);
        assertEq(uint256(token.numCheckpoints(user2)), 2);
        (blockNumber, votes) = token.checkpoints(user2, 1);
        assertEq(votes, 100);
        assertEq(blockNumber, 2);
    }

    // get Prior votes
    function testFailPriorVotesInvalidBlock() public {
        token.getPriorVotes(user1, block.number + 1);
    }

    function testPriorVotesReturnsZeroForNoCheckpoints() public {
        hevm.roll(1);
        assertEq(token.getPriorVotes(user2, 0), 0);
    }

    function testPriorVotesReturnsLatestCheckpoint() public {
        token.transfer(user1, 100); // user1 = delegator
        assertEq(uint256(token.numCheckpoints(user2)), 0);

        hevm.roll(1);

        TokenUser(user1).doDelegate(user2);

        hevm.roll(5);
        assertEq(token.getPriorVotes(user2, 1), 100);
        assertEq(token.getPriorVotes(user2, 4), 100);
    }

    function testPriorVotesReturnsZeroIfNoCheckpoints() public {
        token.transfer(user1, 100); // user1 = delegator
        assertEq(uint256(token.numCheckpoints(user2)), 0);

        hevm.roll(1);

        TokenUser(user1).doDelegate(user2);

        hevm.roll(5);
        assertEq(token.getPriorVotes(user2, 0), 0);
        assertEq(token.getPriorVotes(user2, 3), 100);
    }

    function testPriorVotesReturnsCorrectVotingBalance() public {
        token.transfer(user1, 100); // user1 = delegator
        assertEq(uint256(token.numCheckpoints(user2)), 0);

        hevm.roll(1);
        TokenUser(user1).doDelegate(user2);

        hevm.roll(3);
        TokenUser(user1).doTransfer(user3, 10);

        hevm.roll(5);
        TokenUser(user1).doTransfer(user3, 10);

        hevm.roll(7);
        TokenUser(user3).doTransfer(user1, 20);

        hevm.roll(9);

        assertEq(token.getPriorVotes(user2, 0), 0);
        assertEq(token.getPriorVotes(user2, 1), 100);
        assertEq(token.getPriorVotes(user2, 2), 100);
        assertEq(token.getPriorVotes(user2, 3), 90);
        assertEq(token.getPriorVotes(user2, 4), 90);
        assertEq(token.getPriorVotes(user2, 5), 80);
        assertEq(token.getPriorVotes(user2, 6), 80);
        assertEq(token.getPriorVotes(user2, 7), 100);
        assertEq(token.getPriorVotes(user2, 8), 100);
    }
}
