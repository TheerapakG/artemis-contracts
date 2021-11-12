import { Web3Provider } from "@ethersproject/providers";
import { BigNumberish } from "@ethersproject/bignumber";

export async function advance(provider: Web3Provider, num: BigNumberish) {
  for (let i = await provider.getBlockNumber(); i < num; i++)
    await provider.send("evm_mine", []);
}
