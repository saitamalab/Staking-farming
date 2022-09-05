const hre = require("hardhat");

async function main() {
  //   await hre.run("verify:verify", {
  //     address: "0x6410285e47A98D5885169CB1f120BA976724C370",
  //     constructorArguments:[],
  //     contract: "contracts/Saitama.sol:SAITAMA",
  //   });

  await hre.run("verify:verify", {
    address: "0x642A34f580FBA0D9b82ae8caD9112aAf36B34c1A",
    constructorArguments: [
      "0x0eD81CAe766d5B1a4B3ed4DFbED036be13c6C09C",
      "0xF0360dA6bE15f586D2d673d11323929bf4205D3f",
      "10930109",
      "30000000000",
    ],
    contract: "contracts/Masterchef.sol:MasterChef",
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
