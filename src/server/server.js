import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import Config from './config.json';
import Web3 from 'web3';
import express from 'express';


let config = Config['localhost'];
let web3 = new Web3(new Web3.providers.WebsocketProvider(config.url.replace('http', 'ws')));
web3.eth.defaultAccount = web3.eth.accounts[0];
let flightSuretyApp = new web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
var oracles = [];


// ************************
// ******* UTILS **********
// ************************

function getRandomStatusCode()
{
  let possibleStatuses = 6;
  return (Math.floor( Math.random() * 10 )%(possibleStatuses-1) + 1) * 10;
}

// ************************
// ******** EVENTS ********
// ************************

flightSuretyApp.events.FlightStatusInfo({
  fromBlock: 0
}, function (error, event) {
  if (error) console.error(error)
  else console.info("FlightstatusInfo: " + event);
  }
);

web3.eth.getAccounts().then((accounts) => {
  console.info("FlightSuretyData address: ", config.dataAddress);

  flightSuretyData
  .methods
  .authorizeCaller(config.appAddress)
    .send({from: web3.eth.defaultAccount})
    .then(result => { console.log("FlightSuretyApp authorized: ", config.appAddress); })
    .catch(error => { console.error(error); });

  flightSuretyApp
  .methods
  .REGISTRATION_FEE().call().then(fee => {
    for(let i = 1; i < 20; i++) {
      let account = accounts[i];
      flightSuretyApp
      .methods
      .registerOracle()
      .send({ from: account, value: fee, gas: 9000000 })
      .then(result => {
        flightSuretyApp.methods.getMyIndexes().call({from: account})
        .then(indices =>{
          oracles[account] = indices;
          console.log("Oracle: " + account);
        })
      })
      .catch(error => {
        console.error("Account: " + account + ", message: " + error);
      });
    }
  });

});

flightSuretyApp.events.OracleRequest({
    fromBlock: 0
  }, function (error, event) {
    if (error)
      console.error(error);
    else {
      console.log(event);
      let statusCode = getRandomStatusCode();
      const { index, airline, flight, timestamp } = event.returnValues;

      for(let i = 0; i < oracles.length; i++) {
        let oracle = oracles[i];
        if(oracle.index.includes(index)) {
          flightSuretyApp
          .methods
          .submitOracleResponse(index, airline, flight, timestamp, statusCode)
          .send({from: oracle.address}, (error, result) => {
            if(error) console.error(oracle + ": " +  error);
            else console.info(oracle + ": " + statusCode);
          });
        }
      }
    }
});

const app = express();
app.get('/api', (req, res) => {
  res.send({
    message: 'An API for use with your Dapp!'
  })
})

export default app;


