pragma solidity 0.6.7;

abstract contract StructLike {
    function val(uint256 _id) virtual public view returns (uint256);
}

/**
 * @title LinkedList (Structured Link List)
 * @author Vittorio Minacori (https://github.com/vittominacori)
 * @dev A utility library for using sorted linked list data structures in your Solidity project.
 */
library LinkedList {

    uint256 private constant NULL = 0;
    uint256 private constant HEAD = 0;

    bool private constant PREV = false;
    bool private constant NEXT = true;

    struct List {
        mapping(uint256 => mapping(bool => uint256)) list;
    }

    /**
     * @dev Checks if the list exists
     * @param self stored linked list from contract
     * @return bool true if list exists, false otherwise
     */
    function isList(List storage self) internal view returns (bool) {
        // if the head nodes previous or next pointers both point to itself, then there are no items in the list
        if (self.list[HEAD][PREV] != HEAD || self.list[HEAD][NEXT] != HEAD) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Checks if the node exists
     * @param self stored linked list from contract
     * @param _node a node to search for
     * @return bool true if node exists, false otherwise
     */
    function isNode(List storage self, uint256 _node) internal view returns (bool) {
        if (self.list[_node][PREV] == HEAD && self.list[_node][NEXT] == HEAD) {
            if (self.list[HEAD][NEXT] == _node) {
                return true;
            } else {
                return false;
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Returns the number of elements in the list
     * @param self stored linked list from contract
     * @return uint256
     */
    function range(List storage self) internal view returns (uint256) {
        uint256 i;
        uint256 num;
        (, i) = adj(self, HEAD, NEXT);
        while (i != HEAD) {
            (, i) = adj(self, i, NEXT);
            num++;
        }
        return num;
    }

    /**
     * @dev Returns the links of a node as a tuple
     * @param self stored linked list from contract
     * @param _node id of the node to get
     * @return bool, uint256, uint256 true if node exists or false otherwise, previous node, next node
     */
    function node(List storage self, uint256 _node) internal view returns (bool, uint256, uint256) {
        if (!isNode(self, _node)) {
            return (false, 0, 0);
        } else {
            return (true, self.list[_node][PREV], self.list[_node][NEXT]);
        }
    }

    /**
     * @dev Returns the link of a node `_node` in direction `_direction`.
     * @param self stored linked list from contract
     * @param _node id of the node to step from
     * @param _direction direction to step in
     * @return bool, uint256 true if node exists or false otherwise, node in _direction
     */
    function adj(List storage self, uint256 _node, bool _direction) internal view returns (bool, uint256) {
        if (!isNode(self, _node)) {
            return (false, 0);
        } else {
            return (true, self.list[_node][_direction]);
        }
    }

    /**
     * @dev Returns the link of a node `_node` in direction `NEXT`.
     * @param self stored linked list from contract
     * @param _node id of the node to step from
     * @return bool, uint256 true if node exists or false otherwise, next node
     */
    function next(List storage self, uint256 _node) internal view returns (bool, uint256) {
        return adj(self, _node, NEXT);
    }

    /**
     * @dev Returns the link of a node `_node` in direction `PREV`.
     * @param self stored linked list from contract
     * @param _node id of the node to step from
     * @return bool, uint256 true if node exists or false otherwise, previous node
     */
    function prev(List storage self, uint256 _node) internal view returns (bool, uint256) {
        return adj(self, _node, PREV);
    }

    /**
     * @dev Can be used before `insert` to build an ordered list.
     * @dev Get the node and then `back` or `face` basing on your list order.
     * @dev If you want to order basing on other than `structure.val()` override this function
     * @param self stored linked list from contract
     * @param _struct the structure instance
     * @param _val value to seek
     * @return uint256 next node with a value less than StructLike(_struct).val(next_)
     */
    function sort(List storage self, address _struct, uint256 _val) internal view returns (uint256) {
        if (range(self) == 0) {
            return 0;
        }
        bool exists;
        uint256 next_;
        (exists, next_) = adj(self, HEAD, NEXT);
        while ((next_ != 0) && ((_val < StructLike(_struct).val(next_)) != NEXT)) {
            next_ = self.list[next_][NEXT];
        }
        return next_;
    }

    /**
     * @dev Creates a bidirectional link between two nodes on direction `_direction`
     * @param self stored linked list from contract
     * @param _node first node for linking
     * @param _link  node to link to in the _direction
     */
    function form(List storage self, uint256 _node, uint256 _link, bool _dir) internal {
        self.list[_link][!_dir] = _node;
        self.list[_node][_dir] = _link;
    }

    /**
     * @dev Insert node `_new` beside existing node `_node` in direction `_direction`.
     * @param self stored linked list from contract
     * @param _node existing node
     * @param _new  new node to insert
     * @param _direction direction to insert node in
     * @return bool true if success, false otherwise
     */
    function insert(List storage self, uint256 _node, uint256 _new, bool _direction) internal returns (bool) {
        if (!isNode(self, _new) && isNode(self, _node)) {
            uint256 c = self.list[_node][_direction];
            form(self, _node, _new, _direction);
            form(self, _new, c, _direction);
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Insert node `_new` beside existing node `_node` in direction `NEXT`.
     * @param self stored linked list from contract
     * @param _node existing node
     * @param _new  new node to insert
     * @return bool true if success, false otherwise
     */
    function face(List storage self, uint256 _node, uint256 _new) internal returns (bool) {
        return insert(self, _node, _new, NEXT);
    }

    /**
     * @dev Insert node `_new` beside existing node `_node` in direction `PREV`.
     * @param self stored linked list from contract
     * @param _node existing node
     * @param _new  new node to insert
     * @return bool true if success, false otherwise
     */
    function back(List storage self, uint256 _node, uint256 _new) internal returns (bool) {
        return insert(self, _node, _new, PREV);
    }

    /**
     * @dev Removes an entry from the linked list
     * @param self stored linked list from contract
     * @param _node node to remove from the list
     * @return uint256 the removed node
     */
    function del(List storage self, uint256 _node) internal returns (uint256) {
        if ((_node == NULL) || (!isNode(self, _node))) {
            return 0;
        }
        form(self, self.list[_node][PREV], self.list[_node][NEXT], NEXT);
        delete self.list[_node][PREV];
        delete self.list[_node][NEXT];
        return _node;
    }

    /**
     * @dev Pushes an entry to the head or tail of the linked list
     * @param self stored linked list from contract
     * @param _node new entry to push to the head
     * @param _direction push to the head (NEXT) or tail (PREV)
     * @return bool true if success, false otherwise
     */
    function push(List storage self, uint256 _node, bool _direction) internal returns (bool) {
        return insert(self, HEAD, _node, _direction);
    }

    /**
     * @dev Pops the first entry from the linked list
     * @param self stored linked list from contract
     * @param _direction pop from the head (NEXT) or the tail (PREV)
     * @return uint256 the removed node
     */
    function pop(List storage self, bool _direction) internal returns (uint256) {
        bool exists;
        uint256 adj_;
        (exists, adj_) = adj(self, HEAD, _direction);
        return del(self, adj_);
    }
}
