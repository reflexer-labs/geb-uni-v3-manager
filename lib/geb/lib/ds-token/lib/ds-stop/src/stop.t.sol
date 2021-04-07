/// stop.t.sol -- test for stop.sol

// Copyright (C) 2017  DappHub, LLC

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

import "./stop.sol";

contract User {
    TestThing thing;

    constructor(TestThing thing_) public {
        thing = thing_;
    }

    function doToggle() public {
        thing.toggle();
    }

    function doStop() public {
        thing.stop();
    }

    function doStart() public {
        thing.start();
    }
}

contract TestThing is DSStop {
    bool public x;

    function toggle() public stoppable {
        x = x ? false : true;
    }
}

contract DSStopTest is DSTest {
    TestThing thing;
    User user;

    function setUp() public {
        thing = new TestThing();
        user = new User(thing);
    }

    function testSanity() public {
        thing.toggle();
        assertTrue(thing.x());
    }

    function testFailStop() public {
        thing.stop();
        thing.toggle();
    }

    function testFailStopUser() public {
        thing.stop();
        user.doToggle();
    }

    function testStart() public {
        thing.stop();
        thing.start();
        thing.toggle();
        assertTrue(thing.x());
    }

    function testStartUser() public {
        thing.stop();
        thing.start();
        user.doToggle();
        assertTrue(thing.x());
    }

    function testFailStopAuth() public {
        user.doStop();
    }

    function testFailStartAuth() public {
        user.doStart();
    }
}
