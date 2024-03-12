const { Account, constants, ec, json, stark, Provider, hash, CallData, shortString, RpcProvider, typedData, Contract, uint256, byteArray } = require('starknet');
require('dotenv').config()

const main = async () => {
  const typedDataValidate = {
    types: {
      StarkNetDomain: [
        { name: 'name', type: 'felt' },
        { name: 'version', type: 'felt' },
        { name: 'chainId', type: 'felt' },
      ],
      WTFSBT1155: [
        { name: 'account', type: 'felt' },
        { name: 'soulId', type: 'u256' },
      ],
      u256: [
        { name: "low", type: "felt" },
        { name: "high", type: "felt" },
      ],
    },
    primaryType: 'WTFSBT1155',
    domain: {
      name: 'WTFSBT1155', // put the name of your dapp to ensure that the signatures will not be used by other DAPP
      version: '1',
      chainId: shortString.encodeShortString('SN_GOERLI'), // shortString of 'SN_GOERLI' (or 'SN_MAIN'), to be sure that signature can't be used by other network.
    },
    message: {
      account: process.env.ADDRESS,
      soulId: uint256.bnToUint256(10n),
    },
  };

  console.log(`Public Key: ${ec.starkCurve.getStarkKey(process.env.PRIVATE_KEY)}`)
  
  const provider = new RpcProvider({ nodeUrl: 'https://rpc.starknet-testnet.lava.build/v0_5' });
  const account = new Account(provider, process.env.ADDRESS, process.env.PRIVATE_KEY);
  const signature = (await account.signMessage(typedDataValidate));
  console.log('Sinature:', signature);

  const messageHash = typedData.getMessageHash(typedDataValidate, process.env.ADDRESS);
  console.log('Message Hash:', messageHash);    //0x11357f6641ca52050112c85804ea8f59a98be12c5296af634ad4fef0d9af0f1

  const addressAbi = (await provider.getClassAt(process.env.ADDRESS)).abi;
  const addressContract = new Contract(addressAbi, process.env.ADDRESS, provider);
  try {
    const isValidSignature = await addressContract.is_valid_signature(messageHash, [signature.r, signature.s],);
    console.log('Signature is:', shortString.decodeShortString(isValidSignature));
  }
  catch (error) {
    console.log('Error:', error);
  }
}

const runMain = async () => {
  try {
    await main()
  } catch (error) {
    console.error(error)
  }
}

runMain();