import chai, { expect } from "chai";
import { step } from "mocha-steps";
import {
  solidity,
  MockProvider,
  createFixtureLoader,
  deployContract,
} from "ethereum-waffle";
import { Contract, Wallet } from "ethers";
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from "@ethersproject/units";

import { fixture } from "./shared/fixtures";
import { advance } from "./shared/blocks";
import IFOwithCollateral from "../build/IFOwithCollateral.json";

chai.use(solidity);

const overrides = {
  gasLimit: 9999999,
};

async function setupIFO(admin: Wallet, provider: MockProvider) {
  const loadFixture = createFixtureLoader([admin], provider);
  const thisFixture = await loadFixture(fixture);
  const WONE = thisFixture.WONE;
  const MIS = thisFixture.MIS;
  await MIS.connect(admin).mint(
    await admin.getAddress(),
    parseUnits("1000000", await MIS.decimals())
  );
  const RVRS = thisFixture.RVRS;
  await RVRS.connect(admin).mint(
    await admin.getAddress(),
    parseUnits("1000000", await RVRS.decimals())
  );
  const IFO = await deployContract(
    admin,
    IFOwithCollateral,
    [
      WONE.address, // _lpToken
      RVRS.address, // _offeringToken
      10, // _startBlock
      20, // _endBlock
      parseUnits("1000000", await RVRS.decimals()), // _offeringAmount
      parseUnits("5000000", await WONE.decimals()), // _raisingAmount
      await admin.getAddress(), // _adminAddress,
      MIS.address, // _collateralToken,
      parseUnits("5000", await MIS.decimals()), // _requiredCollateralAmount
    ],
    overrides
  );
  await RVRS.connect(admin).transfer(
    IFO.address,
    parseUnits("1000000", await RVRS.decimals())
  );

  return {
    WONE,
    MIS,
    RVRS,
    IFO,
  };
}

describe("IFOwithCollateral individual test", () => {
  let provider: MockProvider;
  let admin: Wallet;
  let user: Wallet;
  let WONE: Contract;
  let MIS: Contract;
  let RVRS: Contract;
  let IFO: Contract;
  beforeEach(async function () {
    provider = new MockProvider({
      ganacheOptions: {
        hardfork: "istanbul",
        mnemonic: "horn horn horn horn horn horn horn horn horn horn horn horn",
        gasLimit: 9999999,
      },
    });
    [admin, user] = provider.getWallets();
    ({ WONE, MIS, RVRS, IFO } = await setupIFO(admin, provider));
  });

  it("can't deposit without collateral", async () => {
    await advance(provider, 10);

    await WONE.connect(user).deposit({ value: parseEther("1000000") });
    await WONE.connect(user).approve(
      IFO.address,
      parseUnits("1000000", await WONE.decimals())
    );

    await expect(
      IFO.connect(user).deposit(parseUnits("1000000", await WONE.decimals()))
    ).to.be.revertedWith("user needs to stake collateral first");
  });

  it("can't harvest without collateral", async () => {
    await advance(provider, 100);

    await expect(IFO.connect(user).harvest()).to.be.revertedWith(
      "user needs to stake collateral first"
    );
  });
});

describe("IFOwithCollateral works for normal path", () => {
  let provider: MockProvider;
  let admin: Wallet;
  let user: Wallet;
  let WONE: Contract;
  let MIS: Contract;
  let RVRS: Contract;
  let IFO: Contract;
  before(async function () {
    provider = new MockProvider({
      ganacheOptions: {
        hardfork: "istanbul",
        mnemonic: "horn horn horn horn horn horn horn horn horn horn horn horn",
        gasLimit: 9999999,
      },
    });
    [admin, user] = provider.getWallets();
    ({ WONE, MIS, RVRS, IFO } = await setupIFO(admin, provider));
  });

  step("can't deposit before ifo starts", async () => {
    await expect(IFO.connect(user).depositCollateral()).to.be.revertedWith(
      "not ifo time"
    );
  });

  step("at the start, user has no collateral", async () => {
    await advance(provider, 10);
    expect(await IFO.hasCollateral(await user.getAddress())).to.be.false;
  });

  step("deposit collateral fail with insufficient collateral", async () => {
    await expect(IFO.connect(user).depositCollateral()).to.be.revertedWith(
      "depositCollateral:insufficient collateral"
    );
  });

  step("deposit collateral pass with sufficient collateral", async () => {
    await MIS.connect(admin).transfer(
      await user.getAddress(),
      parseUnits("10000", await MIS.decimals())
    );
    await MIS.connect(user).approve(
      IFO.address,
      parseUnits("10000", await MIS.decimals())
    );
    const misBefore = await MIS.balanceOf(await user.getAddress());

    await IFO.connect(user).depositCollateral();

    const misAfter = await MIS.balanceOf(await user.getAddress());
    expect(misBefore.sub(misAfter)).to.be.eq(
      parseUnits("5000", await MIS.decimals())
    );

    expect(await IFO.hasCollateral(await user.getAddress())).to.be.true;
  });

  step("deposit collateral fail with double collateral deposit", async () => {
    await expect(IFO.connect(user).depositCollateral()).to.be.revertedWith(
      "user already staked collateral"
    );
  });

  step("deposit WONE", async () => {
    await WONE.connect(user).deposit({ value: parseEther("1000000") });
    await WONE.connect(user).approve(
      IFO.address,
      parseUnits("1000000", await WONE.decimals())
    );
    const woneBefore = await WONE.balanceOf(await user.getAddress());

    await IFO.connect(user).deposit(
      parseUnits("1000000", await WONE.decimals())
    );

    const woneAfter = await WONE.balanceOf(await user.getAddress());
    expect(woneBefore.sub(woneAfter)).to.be.eq(
      parseUnits("1000000", await WONE.decimals())
    );
    expect(await IFO.getUserAllocation(await user.getAddress())).to.be.eq(
      1000000
    );
  });

  step("fail if harvest before ifo ends", async () => {
    await expect(IFO.connect(user).harvest()).to.be.revertedWith(
      "not harvest time"
    );
  });

  step("can harvest at the end of ifo", async () => {
    await advance(provider, 90);
    const misBeforeHarvest = await MIS.balanceOf(await user.getAddress());
    const woneBeforeHarvest = await WONE.balanceOf(await user.getAddress());
    const rvrsBeforeHarvest = await RVRS.balanceOf(await user.getAddress());

    await IFO.connect(user).harvest();

    const misAfterHarvest = await MIS.balanceOf(await user.getAddress());
    const woneAfterHarvest = await WONE.balanceOf(await user.getAddress());
    const rvrsAfterHarvest = await RVRS.balanceOf(await user.getAddress());

    expect(misAfterHarvest.sub(misBeforeHarvest)).to.be.eq(
      parseUnits("5000", await MIS.decimals())
    );
    expect(woneAfterHarvest.sub(woneBeforeHarvest)).to.be.eq(
      parseUnits("0", await WONE.decimals())
    );
    expect(rvrsAfterHarvest.sub(rvrsBeforeHarvest)).to.be.eq(
      parseUnits("200000", await RVRS.decimals())
    );
  });

  step("fail if double harvest", async () => {
    await expect(IFO.connect(user).harvest()).to.be.revertedWith(
      "already claimed"
    );
  });
});
