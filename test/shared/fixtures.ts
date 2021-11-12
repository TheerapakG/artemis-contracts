import { Wallet, Contract } from "ethers";
import { Web3Provider } from "@ethersproject/providers";
import { deployContract } from "ethereum-waffle";

import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20PresetMinterPauser.json";
import WETH9 from "canonical-weth/build/contracts/WETH9.json";

const overrides = {
  gasLimit: 9999999,
};

interface Fixture {
  WONE: Contract;
  MIS: Contract;
  RVRS: Contract;
}

export async function fixture(
  [wallet]: Wallet[],
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  provider: Web3Provider
): Promise<Fixture> {
  // deploy tokens
  const WONE = await deployContract(wallet, WETH9, undefined, overrides);
  const MIS = await deployContract(
    wallet,
    ERC20,
    ["TestArtemis", "MIS"],
    overrides
  );
  const RVRS = await deployContract(
    wallet,
    ERC20,
    ["TestReverse", "RVRS"],
    overrides
  );

  return {
    WONE,
    MIS,
    RVRS,
  };
}
