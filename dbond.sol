pragma solidity ^0.4.24;

contract dbond {
   address owner;
	
	struct blockinfo {
		uint256 outstanding;							// remaining debt at block
		uint256 dividend;							// % dividend users can claim
		uint256 value;								// actual ether value at block
		uint256 index;                      					// used in frontend for async checks
	}
	struct debtinfo {
		uint256 idx;								// dividend array position
		uint256 pending;							// pending balance at block
		uint256 initial;							// initial ammount for stats
	}
    	struct account {
		uint256 ebalance;                                                       // ether balance
		mapping(uint256 => debtinfo) owed;					// keeps track of outstanding debt 
	}
	
	uint256 public bondsize;							// size of the current bond
	uint256 public interest;							// interest to pay clients expressed in ETH(ie: 10% is 10ETH)
	uint256 public IDX;								// current dividend block
	mapping(uint256 => blockinfo) public blockData;					// dividend block data
	mapping(address => account) public balances;					// public user balances
	bool public selling;								// are we selling bonds?

	constructor() public {                                                     
        	owner = msg.sender;   
	}
	
	modifier onlyOwner() { 
		require(msg.sender == owner, "only owner can call."); 
		_; 
	}
	
	modifier canBuy() {
		require(selling, "bonds are not selling");
		if(bondsize > 0)
			require(msg.value <= bondsize-blockData[IDX].value, "larger than bond");
		_;
	}
	
	// sets the maximum ammount to receive
	// cannot be lowered unless this bond sale is closed(prevents overflows)
	function setBondSize(uint256 _bondsize) public onlyOwner {
		require(_bondsize >= bondsize, "for a reduced bond size please end the current sale and make a new one");
		bondsize = _bondsize;
	}
	
	// Sets the interest rate for all future purchases
	// current outstanding debt is not affected by this
	function setInterestRate(uint256 _interest) public onlyOwner {
		interest = _interest;
	}
	
	// enables a bond sale
	// if the bondsize is set to 0, the sale becomes akin to a continous bond contract
	function sellBond(uint256 _bondsize, uint256 _interest) public onlyOwner {
		selling = true;
		bondsize = _bondsize;
		interest = _interest;
	}
	
	// terminates a bond sale, the outstanding still needs to be paid off
	function endBondSale() public onlyOwner {
		selling = false;
		blockData[IDX].dividend = 0;
		_nextblock();
	}
  	
	// makes a payment to all outstanding debt at block IDX
	// advances the bond block by 1 and distributes in terms of percentage
	function payBond() public payable onlyOwner {
		// keeps track of the actual outstanding, prevents ether leaking
		require(msg.value > 0, "zero payment detected");
		require(msg.value <= blockData[IDX].outstanding, "overpayment will result in lost Ether");
		// actual payment % that goes to all buyers
		blockData[IDX].dividend = (msg.value * 100 ether) / blockData[IDX].outstanding;
		_nextblock();
		blockData[IDX].outstanding -= (blockData[IDX-1].outstanding * blockData[IDX-1].dividend ) / 100 ether;
	}
	
	function buyBond() public payable canBuy {
		_bond(msg.sender, msg.value);
	}
	
	// withdraws ether to the user account
	// user has to claim his money by calling getOwed first
	function withdraw() public {
		require(balances[msg.sender].ebalance > 0, "not enough to withdraw");
		uint256 sval = balances[msg.sender].ebalance;
		balances[msg.sender].ebalance = 0;
		msg.sender.transfer(sval);
		emit event_withdraw(msg.sender, sval);
	}
		
	// returns the ammount that is owed to that user at a specific block
	function owedAt(uint256 blk) public view returns(uint256, uint256, uint256) { 
		return (balances[msg.sender].owed[blk].idx, 
			balances[msg.sender].owed[blk].pending, 
			balances[msg.sender].owed[blk].initial	); 
	}
	
	// actual buy calculation, adds to the outstanding debt
	// interest is calculated and added here according to the current rate
	function _bond(address addr, uint256 val) internal { 
		uint256 tval = val + ((val * interest) / 100 ether);
		balances[owner].ebalance += val;                                                                                       
		blockData[IDX].value += val;
      		blockData[IDX].outstanding += tval;                                    
		balances[addr].owed[IDX].idx = IDX;							            
		balances[addr].owed[IDX].pending += tval;                              
		balances[addr].owed[IDX].initial += tval;
		emit event_buy(val);
	}
	
	// moves the bond block forward by 1, carries over all previous debt
	function _nextblock() internal {
		IDX += 1;															
		blockData[IDX].index = IDX;     

		// previous debt rolls over to next block
		blockData[IDX].outstanding = blockData[IDX-1].outstanding;			           
		emit event_newblk(IDX);		
	}

	// users call this per bond they have purchased in order to claim their money
	// their total owed for the bond goes down and is added to their ebalance
	function getOwed(uint256 blk) public {
		require(balances[msg.sender].owed[blk].idx < IDX && blk < IDX, "current block");
		uint256 cdiv = 0;
		for(uint256 i = 0; i < 1000; i++) {
			cdiv = (balances[msg.sender].owed[blk].pending * 
				blockData[balances[msg.sender].owed[blk].idx].dividend ) / 100 ether;
			cdiv = (cdiv > balances[msg.sender].owed[blk].pending)? 
						balances[msg.sender].owed[blk].pending : cdiv;          
			balances[msg.sender].owed[blk].idx += 1;                           
			balances[msg.sender].owed[blk].pending -= cdiv;
			balances[msg.sender].ebalance += cdiv;
			if( balances[msg.sender].owed[blk].pending == 0 || 
			    balances[msg.sender].owed[blk].idx >= IDX ) 
				return;
		}
	}

    // events ------------------------------------------------------------------
    event event_withdraw(address addr, uint256 val);
    event event_newblk(uint256 idx);
    event event_buy(uint256 val);
}
