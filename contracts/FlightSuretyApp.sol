pragma solidity ^0.5.0;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    FlightSuretyData flightSuretyData;
    uint256 public constant AIRLINE_REGISTRATION_FEE = 10 ether;
    uint256 constant MAXIMUM_INSURANCE_FEE = 1 ether;


    address private contractOwner;          // Account used to deploy contract
    bool private operational = true;
    uint8 private constant MINIMUM_AIRLINES_FOR_CONSENSUS = 4;
 
    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        // Modify to call data contract's status
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireCorrectFundingFee()
    {
        require(msg.value >= AIRLINE_REGISTRATION_FEE, "The fee submitted is too low. The required fee is of 10 ether");
        _;
    }

    modifier requireAirlineEnqueued()
    {
        require(flightSuretyData.isAirlineEnqueued(msg.sender), "You first need to enqueue your airline.");
        _;
    }

    modifier requireCorrectInsuringFee()
    {
        require(msg.value <= MAXIMUM_INSURANCE_FEE && msg.value > 0, "amount too low or too high. Maximum is 1 eth, minimum 0 eth.");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    event AirlineRegistered(address airline);
    event AirlineFunded(address airline);
    event VotedInAirline(address votingAirline, address votedInAirline);
    event CreditsWithdrawn(address customer, uint256 amount);

    /**
    * @dev Contract constructor
    *
    */
    // we can assume the app is created only once,
    // so the registration of the first airline
    // can happen here
    constructor(address dataContract, address firstAirline) public
    {
        contractOwner = msg.sender;

        operational = true; // ?

        flightSuretyData = FlightSuretyData(dataContract);
        flightSuretyData.registerAirline(firstAirline);

        emit AirlineRegistered(firstAirline);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns(bool)
    {
        return operational;  // Modify to call data contract's status
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

  
   /**
    * @dev Add an airline to the registration queue
    *
    */   
    function registerAirline(address newAirline) external requireIsOperational() returns(bool success, uint256 votes)
    {
        uint256 registeredAirlinesLength = flightSuretyData.registeredAirlinesSize();

        if(registeredAirlinesLength >= MINIMUM_AIRLINES_FOR_CONSENSUS) {
            // need consensus
            flightSuretyData.enqueueAirline(newAirline);

        } else {
            // too few airlines still
            flightSuretyData.registerAirline(newAirline);
        }

        return (success, 0);
    }


    function voteAirlineIn(address airline) public
    {
        address votingAirline = msg.sender;
        uint256 registeredAirlinesLength = flightSuretyData.registeredAirlinesSize();
        uint256 requiredConsensus = registeredAirlinesLength.div(2);
        flightSuretyData.addVotingAirline(airline, votingAirline);
        (address[] memory approvingAirlines, bool enq) = flightSuretyData.getApplicantData(airline);

        uint256 votes = approvingAirlines.length;
        if(votes == requiredConsensus) {
            flightSuretyData.registerAirline(airline);
            flightSuretyData.changeEnqueueStatus(airline, !enq);

            emit VotedInAirline(votingAirline, airline);
        }

    }

    function submitFunding(address airline) public payable
    requireCorrectFundingFee
    requireAirlineEnqueued
    {
        flightSuretyData.fundAirline(airline, msg.value);

        emit AirlineFunded(airline);
    }

   /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight(string calldata flight, uint256 timestamp) external
    {
        flightSuretyData.registerFlight(msg.sender, flight, timestamp);

        // emit FlightRegistered(msg.sender, flight, timestamp);

    }

    
   /**
    * @dev Called after oracle has updated flight status
    *
    */  
    function processFlightStatus(address airline,
                                string memory flight,
                                uint256 timestamp,
                                uint8 statusCode) internal pure
    {

    }

    function withdrawCredit() public
    requireIsOperational
    {
        require(flightSuretyData.getCustomerCredit(msg.sender) > 0, "Customer has nothing credited.");

        uint256 amount = flightSuretyData.pay(msg.sender);
        msg.sender.transfer(amount);

        emit CreditsWithdrawn(msg.sender, amount);
    }


    // MSJ: For passengers to purchase insurance
    function purchaseFlightInsurance(string calldata flight, address airline, uint256 timestamp) payable external
    requireCorrectInsuringFee
    returns (bool)
    {
        flightSuretyData.purchaseInsurance(msg.sender, flight, airline, timestamp, msg.value);
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(address airline, string calldata flight, uint256 timestamp) external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
                                                requester: msg.sender,
                                                isOpen: true
                                            });

        emit OracleRequest(index, airline, flight, timestamp);
    } 


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;    

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);

    modifier requireRegistrationFee()
    {
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");
        _;
    }

    // Register an oracle with the contract
    function registerOracle() external payable
    requireRegistrationFee
    {
        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
    }

    function getMyIndexes() view external returns(uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
                        (
                            uint8 index,
                            address airline,
                            string calldata flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }

    // Luca: added "memory" bc of warnings
    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);
        
        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion

}   

// decoupling through interface
interface FlightSuretyData {
    function registerAirline(address airline) external;
    function enqueueAirline(address airline) external;
    function fundAirline(address airline, uint256 amount) external;
    function registeredAirlinesSize() external view returns(uint256);
    function isAirlineEnqueued(address airline) external view returns (bool);
    function getApplicantData(address airline) external view returns(address[] memory, bool);
    function addVotingAirline(address incomingAirline, address votingAirline) external;
    function changeEnqueueStatus(address incomingAirline, bool status) external;
    function purchaseInsurance(address customer, string calldata flight, address airline, uint256 timestamp, uint256 amount) external payable returns (bool);
    function registerFlight(address airline, string calldata flight, uint256 timestamp) external;
    function getCustomerCredit(address customer) external view returns(uint256);
    function pay(address customer) external returns(uint256);
}
