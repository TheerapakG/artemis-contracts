import pytest

from brownie import accounts, reverts, chain


@pytest.fixture
def mis(ArtemisToken):
    token = accounts[0].deploy(ArtemisToken)
    token.mint(accounts[0], 1e30)
    token.transfer(accounts[1], 1e25, {'from': accounts[0]})
    token.transfer(accounts[2], 1e25, {'from': accounts[0]})
    token.transfer(accounts[3], 1e25, {'from': accounts[0]})
    return token


@pytest.fixture
def wone(ArtemisToken):
    token = accounts[0].deploy(ArtemisToken)
    token.mint(accounts[0], 1e30)
    token.transfer(accounts[1], 1e25, {'from': accounts[0]})
    token.transfer(accounts[2], 1e25, {'from': accounts[0]})
    token.transfer(accounts[3], 1e25, {'from': accounts[0]})
    return token


@pytest.fixture
def rvrs(ArtemisToken):
    token = accounts[0].deploy(ArtemisToken)
    token.mint(accounts[0], 1e30)
    return token


@pytest.fixture
def ifo1(IFOwithCollateral, mis, wone, rvrs):
    offeringAmount = int(1e18 * 1000)

    IFO = IFOwithCollateral.deploy(
        wone,
        rvrs,
        0,
        100,
        offeringAmount,
        int(1e18 * 1000),
        accounts[0],
        mis,
        int(1e18 * 800),
        {'from': accounts[0]}
    )

    # Send ifo contract enough rvrs
    rvrs.transfer(IFO, offeringAmount, {'from': accounts[0]})

    return IFO


def test_ifo1_user_workflow_green_path(ifo1, mis, wone, rvrs):
    """Test the normal workflow assuming everything happens in the right order"""

    # Deposit Collateral
    assert not ifo1.hasCollateral(accounts[1]), "User shouldn't have collateral staked yet"

    mis.approve(ifo1, 1e30, {'from': accounts[1]})
    mis_bal_before = mis.balanceOf(accounts[1])

    ifo1.depositCollateral({'from': accounts[1]})

    mis_bal_after = mis.balanceOf(accounts[1])
    assert int((mis_bal_before - mis_bal_after)/1e18) == 800, "MIS balance is messed up"
    assert ifo1.hasCollateral(accounts[1]), "User didn't get credit for staking collateral"

    # Deposit WONE
    wone.approve(ifo1, 1e30, {'from': accounts[1]})
    wone_bal_before = wone.balanceOf(accounts[1])

    ifo1.deposit(int(1e20), {'from': accounts[1]})

    wone_bal_after = wone.balanceOf(accounts[1])
    assert int((wone_bal_before - wone_bal_after)/1e18) == 100, "WONE balance is messed up"
    assert ifo1.getUserAllocation(accounts[1]) == 1000000, "User didn't get credit for depositing WONE"

    # Validate harvest doesn't work yet - this should revert
    with reverts('not harvest time'):
        ifo1.harvest({'from': accounts[1]})

    # Go to end of IFO and harvest
    chain.mine(100)
    mis_bal_before = mis.balanceOf(accounts[1])
    wone_bal_before = wone.balanceOf(accounts[1])
    rvrs_bal_before = rvrs.balanceOf(accounts[1])

    ifo1.harvest({'from': accounts[1]})

    mis_bal_after = mis.balanceOf(accounts[1])
    wone_bal_after = wone.balanceOf(accounts[1])
    rvrs_bal_after = rvrs.balanceOf(accounts[1])

    assert int((mis_bal_after - mis_bal_before)/1e18) == 800, "MIS balance is messed up"
    assert int((wone_bal_after - wone_bal_before)/1e18) == 0, "WONE balance is messed up"
    assert int((rvrs_bal_after - rvrs_bal_before)/1e18) == 100, "RVRS balance is messed up"

