var tokenFactory = artifacts.require("proofTokenFactory");
var hldBurner = artifacts.require("hldBurner");

let hldToken = "0xCA1308E38340C69E848061aA2C3880daeB958187";
let uniRouter = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
let lockerAddress = "0xE2fE530C047f2d85298b07D9333C05737f1435fB";

module.exports = async function(deployer, network, accounts) {

  await deployer.deploy(hldBurner, hldToken, uniRouter);
  const hldBurnerInstance = await hldBurner.deployed();

  await deployer.deploy(tokenFactory, uniRouter, hldBurnerInstance.address, lockerAddress);
  const tokenFactoryInstance = await tokenFactory.deployed();


}