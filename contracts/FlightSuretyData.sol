pragma solidity ^0.5.0;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codes
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    // address[] registeredAirlines; // i.e. funded + voted in
    mapping(address => uint256) private airlinesFunding;
    mapping(address => bool) private registeredAirlines;
    uint256 private registeredAirlinesCount = 0;

    struct RegistrationQueue {
        address[] approvingAirlines;
        bool enqueued;
    }

    mapping(address => RegistrationQueue) private registrationQueue;


    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 timestamp;
        string flight;
        address airline;
    }

    mapping(bytes32 => Flight) private flights;


    struct Insurance {
        bytes32 flightKey;
        uint256 insuredAmount;
        bool payedOut;
    }

    mapping(address => Insurance) private insurances; // key is the customer
    mapping(bytes32 => address[]) private insuredCustomers;
    mapping(address => uint256) private customersCredit;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/
    event AirlineEnqueued(address airline);
    event AirlineFunded(address airline);
    event FlightRegistered(string flight, uint256 timestamp, address airline);
    event InsurancePurchased(address customer, bytes32 flightKey);
    event InsureeCredited(address airline, address customer, bytes32 flightKey, uint256 amount);


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
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    modifier requireAirlineIsFunded()
    {
        require(airlinesFunding[msg.sender] > 0, "Airline has no funds");
        _;
    }

    modifier requireAirlineIsRegistered()
    {
        require(registeredAirlines[msg.sender] == true, "Airline is not registered");
        _;
    }

    // modifier requireNotAlreadyEnqueued(address airline)
    // {
    //     require(!registeredAirlines[airline] || registrationQueue[airline].enqueued, "Contract is currently not operational");
    //     _;

    // }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() public view returns(bool)
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus(bool mode) external
    requireContractOwner
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor() public
    {
        contractOwner = msg.sender;
        registeredAirlinesCount = 1;
    }

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline(address airline) external
    requireIsOperational
    {
        registeredAirlines[airline] = true;
        registeredAirlinesCount += 1;
        airlinesFunding[airline] = 0;
    }


    function enqueueAirline(address airline) external
    requireIsOperational
    // requireNotAlreadyEnqueued(airline)
    {
        registrationQueue[airline].enqueued = true;

        emit AirlineEnqueued(airline);
    }

    function fundAirline(address airline, uint256 amount) external
    {
        airlinesFunding[airline] += amount;

        emit AirlineFunded(airline);
    }

    /** TOIMPLEMENT
     */
    function authorizeCaller(address someone) external pure
    {

    }

    function isAirlineEnqueued(address airline) external view
    requireIsOperational()
    returns (bool)
    {
        return registrationQueue[airline].enqueued;
    }

    function registeredAirlinesSize() external view returns(uint256)
    {
        return registeredAirlinesCount;
    }

    function getApplicantData(address airline) external view returns(address[] memory, bool)
    {
        // return registrationQueue[airline];
        return (registrationQueue[airline].approvingAirlines, registrationQueue[airline].enqueued);
    }

    function addVotingAirline(address incomingAirline, address votingAirline) external
    {
        registrationQueue[incomingAirline].approvingAirlines.push(votingAirline);
    }

    function changeEnqueueStatus(address incomingAirline, bool status) external
    {
        registrationQueue[incomingAirline].enqueued = status;
    }

    function isAirline(address airline) internal view returns(bool)
    {
        // need to check if it is a boolean
        if(registeredAirlines[airline] == true)
            return true;
        else
            return false;
    }
    
   /**
    * @dev Buy insurance for a flight
    *
    */
    function purchaseInsurance(address customer, string calldata flight, address airline, uint256 timestamp, uint256 amount) external payable
    requireIsOperational
    returns (bool)
    {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        require(flights[flightKey].isRegistered == true, "This flight is unregistered");

        insurances[customer].insuredAmount = amount;
        insurances[customer].payedOut = false;
        insurances[customer].flightKey = flightKey;
        insuredCustomers[flightKey].push(customer);

        emit InsurancePurchased(customer, flightKey);
    }

    // MSJ: Register Flight
    function registerFlight(address airline, string calldata flight, uint256 timestamp) external
    requireIsOperational
    requireAirlineIsFunded
    requireAirlineIsRegistered
    {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        require(flights[flightKey].isRegistered == false, "Flight was already registered");

        flights[flightKey].isRegistered = true;
        flights[flightKey].statusCode = STATUS_CODE_UNKNOWN;
        flights[flightKey].flight = flight;
        flights[flightKey].timestamp = timestamp;
        flights[flightKey].airline = airline;

        emit FlightRegistered(flight, timestamp, airline);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(address airline, string calldata flight, uint256 timestamp) external
    requireIsOperational
    requireAirlineIsFunded
    requireAirlineIsRegistered
    {

        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        Flight memory flightStruct = flights[flightKey];

        require(flightStruct.isRegistered, "Flight is unregistered");
        require(flightStruct.statusCode != STATUS_CODE_UNKNOWN, "Flight status is unkonwn");
        require(flightStruct.statusCode != STATUS_CODE_ON_TIME, "Flight was on time");
        address[] memory customers = insuredCustomers[flightKey];

        for (uint256 i = 0; i < customers.length; i++)
        {
            address customer = customers[i];
            Insurance memory insurance = insurances[customer];

            if(insurance.flightKey == flightKey && !(insurance.payedOut)) {
                uint256 creditingAmount = insurance.insuredAmount.mul(150).div(100);

                // first debit
                airlinesFunding[airline] -= creditingAmount;

                // then credit
                customersCredit[customer] += creditingAmount;

                insurances[customer].payedOut = true;
                emit InsureeCredited(airline, customer, flightKey, creditingAmount);
            }
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address customer) external returns(uint256)
    {
        uint256 payingAmount = customersCredit[customer];
        // first debit
        customersCredit[customer] = 0;
        // then credit
        return payingAmount;
    }


    function getCustomerCredit(address customer) external view returns(uint256)
    {
        return customersCredit[customer];
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund() public payable
    {

    }

    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() external payable
    {
        fund();
    }


}

