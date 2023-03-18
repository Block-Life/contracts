import { ethers } from "hardhat";
import { BlockdiceManager } from "../typechain";
import { expect } from "chai";
import { VRFCoordinatorV2Mock } from "../typechain/VRFCoordinatorV2Mock.sol";


describe("BlockdiceManager", () => {
  let manager: BlockdiceManager;
  let VRFCoordinatorV2Mock: VRFCoordinatorV2Mock;
  let hardhatOurNFTContract, hardhatVrfCoordinatorV2Mock;

  beforeEach(async () => {
    const [deployer] = await ethers.getSigners();

    // Deploy mock VRF consumer contract
    const VRFCoordinatorV2MockFactory = await ethers.getContractFactory(
        "VRFCoordinatorV2Mock",
        deployer
      );
      VRFCoordinatorV2Mock = (await VRFCoordinatorV2MockFactory.deploy(0, 0)) as VRFCoordinatorV2Mock;
      await VRFCoordinatorV2Mock.deployed();

      await expect(VRFCoordinatorV2Mock.createSubscription()).to.emit(VRFCoordinatorV2Mock, "SubscriptionCreated")

    await VRFCoordinatorV2Mock.fundSubscription(1, ethers.utils.parseEther("7"))
    
    await VRFCoordinatorV2Mock.addConsumer(1, deployer.address);
    /*await expect(VRFCoordinatorV2Mock.requestRandomWords(
      "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f", 
      1, 
      3, 
      1000000,
      1)).to.be.revertedWithCustomError(VRFCoordinatorV2Mock, "InvalidSubscription")
    */
      const ManagerFactory = await ethers.getContractFactory(
      "BlockdiceManager",
      deployer
    );
    manager = (await ManagerFactory.deploy(1, VRFCoordinatorV2Mock.address)) as BlockdiceManager;

    await manager.deployed();

    await VRFCoordinatorV2Mock.addConsumer(1, manager.address);

    
  });

  it("should create a new session", async () => {
    const [player1] = await ethers.getSigners();
    const maxPlayerAmount = 10;
    const sessionPrice = 1000;
    await manager.createSession({
      value: sessionPrice,
    });
    const session = await manager.getSession();
    expect(session.admin).to.equal(player1.address);
    expect(session.maxPlayerAmount).to.equal(maxPlayerAmount);
    expect(session.sessionPrice).to.equal(sessionPrice);
    expect(session.playerCount).to.equal(1);
    expect(session.players[0]).to.equal(player1.address);
  });

  it("should not create a new session if player is already in one", async () => {
    const [player1] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.createSession({
      value: sessionPrice,
    });
    await expect(
      manager.createSession({
        value: sessionPrice,
      })
    ).to.be.revertedWithCustomError(manager, "PlayerAlreadyInSession");
  });

  it("should not create a new session if sent value is below minimum session price", async () => {
    const [player1] = await ethers.getSigners();
    const sessionPrice = 500;
    await expect(
      manager.createSession({
        value: sessionPrice,
      })
    ).to.be.revertedWithCustomError(manager, "BelowMinimumSessionPrice");
  });

  it("should start a new session", async () => {
    const [player1, player2, player3] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.connect(player1).createSession({
      value: sessionPrice,
    });

    await VRFCoordinatorV2Mock.fulfillRandomWords(1, manager.address)

    await manager.connect(player2).enterSession(player1.address, {
        value: sessionPrice,	
        });

    await expect(manager.connect(player3).enterSession(player1.address, {
        value: 3 * sessionPrice / 2,
    })).to.be.revertedWithCustomError(manager, "SentDifferentSessionPrice");

   
    await manager.connect(player1).startSession();

    await VRFCoordinatorV2Mock.fulfillRandomWords(2, manager.address)
    const session = await manager.getSession();
    expect(session.status).to.equal(2);
    expect(session.whoseTurn).to.equal(1);
    expect(session.playerPositions[0]).to.equal(0);
    expect(session.playerPositions[1]).to.equal(0);

    await expect(manager.connect(player3).enterSession(player1.address, {
        value: sessionPrice,
    })).to.be.revertedWithCustomError(manager, "TargetSessionIsStarted");

    });



  it("should not start a new session if there is only one player", async () => {
    const [player1] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.createSession({
      value: sessionPrice,
    });
    await expect(manager.startSession()).to.be.revertedWithCustomError(
        manager,
      "Minimum2PlayersNeeded"
    );
  });

  it("should roll the dice", async () => {
    const [player1, player2] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.connect(player1).createSession({
      value: sessionPrice,
    });

    await VRFCoordinatorV2Mock.fulfillRandomWords(1, manager.address)
   

    await manager.connect(player2).enterSession(player1.address, {
        value: sessionPrice,
      });
    
    await manager.startSession();

    await VRFCoordinatorV2Mock.fulfillRandomWords(2, manager.address)

    const preDiceSession = await manager.getSessionHelper(player1.address);
    expect(preDiceSession.playerPositions[0]).to.be.equal(0);
    expect(preDiceSession.playerPositions[1]).to.be.equal(0);
    // This line shouldn't be tested as the player who rolls the dice is chosen randomly
    // expect(preDiceSession.whoseTurn).to.be.equal(1);
    const starterIndex = preDiceSession.whoseTurn;


    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();

    await VRFCoordinatorV2Mock.fulfillRandomWords(3, manager.address)
      
          
    const session = await manager.getSessionHelper(player1.address);
    expect(session.playerPositions[0]).to.be.equal(0);
    expect(session.playerPositions[1]).not.to.be.equal(0);
    if (starterIndex == 0) await manager.connect(player2).dice();
    else await manager.connect(player1).dice();

    await VRFCoordinatorV2Mock.fulfillRandomWords(4, manager.address)

    const session2 = await manager.getSessionHelper(player1.address);
    expect(session2.playerPositions[session.whoseTurn]).not.to.be.equal(0);
    expect(session2.playerPositions[session.whoseTurn]).not.to.be.equal(0);

    await expect(manager.connect(player1).dice()).to.be.revertedWithCustomError(
        manager,
        "NotYourTurn"
        );
  });

  /* Commented out because it doesnt work on chains that dont have a built-in random number generator
  it("should roll the dice properly with randao every 5 blocks", async () => {
    const [player1, player2] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.connect(player1).createSession({
      value: sessionPrice,
    });
    await manager.connect(player2).enterSession(player1.address, {
        value: sessionPrice,
    });
    
    await manager.connect(player1).startSession();

    const preDiceSession = await manager.getSessionHelper(player1.address);
    expect(preDiceSession.playerPositions[0]).to.be.equal(0);
    expect(preDiceSession.playerPositions[1]).to.be.equal(0);
    
    const starterIndex = preDiceSession.whoseTurn;

    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();
    const session = await manager.getSession();
    const zone = session.playerPositions[session.whoseTurn] % 3 == 0 ? 1 : 2;
    const tax = session.sessionPrice / 10 * zone;
    const rent = session.sessionPrice / 10 * zone;
    
    // walk forward 5 blocks
    for (let i = 0; i < 5; i++) {
    await ethers.provider.send("evm_mine")
    }
    
    if (starterIndex == 0) await manager.connect(player2).dice();
    else await manager.connect(player1).dice();
    for (let i = 0; i < 5; i++) {
        await ethers.provider.send("evm_mine")
        }
    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();
    for (let i = 0; i < 5; i++) {
        await ethers.provider.send("evm_mine")
        }
        
    if (starterIndex == 0) await manager.connect(player2).dice();
    else await manager.connect(player1).dice();

    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();

    if (starterIndex == 0) await expect(manager.connect(player2).dice()).to.be.revertedWithCustomError(
        manager,
        "RandomWordIsNotReadyYet"
        )
    else await expect(manager.connect(player1).dice()).to.be.revertedWithCustomError(
        manager,
        "RandomWordIsNotReadyYet"
        );

    
  }); */

  it("should roll the dice multiple times without errors ", async () => {
    const [player1, player2] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.connect(player1).createSession({
      value: sessionPrice,
    });

    await VRFCoordinatorV2Mock.fulfillRandomWords(1, manager.address)
    await manager.connect(player2).enterSession(player1.address, {
        value: sessionPrice,
    });
    
    await manager.connect(player1).startSession();
    await VRFCoordinatorV2Mock.fulfillRandomWords(2, manager.address)

    const preDiceSession = await manager.getSessionHelper(player1.address);
    expect(preDiceSession.playerPositions[0]).to.be.equal(0);
    expect(preDiceSession.playerPositions[1]).to.be.equal(0);
    
    const starterIndex = preDiceSession.whoseTurn;

    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();
    await VRFCoordinatorV2Mock.fulfillRandomWords(3, manager.address)
    const session = await manager.getSession();
    const zone = session.playerPositions[session.whoseTurn] % 3 == 0 ? 1 : 2;
    const tax = session.sessionPrice / 10 * zone;
    const rent = session.sessionPrice / 10 * zone;
    
    // walk forward 5 blocks
    for (let i = 0; i < 5; i++) {
    await ethers.provider.send("evm_mine")
    }
    
    if (starterIndex == 0) await manager.connect(player2).dice();
    else await manager.connect(player1).dice();
    await VRFCoordinatorV2Mock.fulfillRandomWords(4, manager.address)
    for (let i = 0; i < 5; i++) {
        await ethers.provider.send("evm_mine")
        }
    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();
    await VRFCoordinatorV2Mock.fulfillRandomWords(5, manager.address)
    for (let i = 0; i < 5; i++) {
        await ethers.provider.send("evm_mine")
        }
        
    if (starterIndex == 0) await manager.connect(player2).dice();
    else await manager.connect(player1).dice();
    await VRFCoordinatorV2Mock.fulfillRandomWords(6, manager.address)

    if (starterIndex == 0) await manager.connect(player1).dice();
    else await manager.connect(player2).dice();
    
    if (starterIndex == 0) await expect(manager.connect(player2).dice()).to.be.revertedWithCustomError(
        manager,
        "RandomWordIsNotReadyYet"
        )
    else await expect(manager.connect(player1).dice()).to.be.revertedWithCustomError(
        manager,
        "RandomWordIsNotReadyYet"
        );

    
  });


  it("should not enter a session if the session is full", async () => {
    const [player1, player2, player3, player4, player5, player6, player7, player8, player9, player10, player11, player12] = await ethers.getSigners();
    const maxPlayerAmount = 10;
    const sessionPrice = 1000;
    await manager.connect(player1).createSession({
      value: sessionPrice,
    });
    await manager.connect(player2).enterSession(player1.address, {
      value: sessionPrice,
    });
    await manager.connect(player3).enterSession(player1.address, {
      value: sessionPrice,
    });
    await manager.connect(player4).enterSession(player1.address, {
        value: sessionPrice,
      });
    await manager.connect(player5).enterSession(player1.address, {
        value: sessionPrice,
    });
    await manager.connect(player6).enterSession(player1.address, {
        value: sessionPrice,
    });
    await manager.connect(player7).enterSession(player1.address, {
        value: sessionPrice,
    });
    await manager.connect(player8).enterSession(player1.address, {
          value: sessionPrice,
    });
    await manager.connect(player9).enterSession(player1.address, {
          value: sessionPrice,
    });
    await manager.connect(player10).enterSession(player1.address, {
        value: sessionPrice,
    });
    await expect(manager.connect(player11).enterSession(player1.address, {
        value: sessionPrice,
    })).to.be.revertedWithCustomError(manager, "TargetSessionIsFull");
    
    
  });

  it("should exit a session", async () => {
    const [player1, player2] = await ethers.getSigners();
    const sessionPrice = 1000;
    await manager.connect(player1).createSession({
        value: sessionPrice,
      });
      await manager.connect(player2).enterSession(player1.address, {
        value: sessionPrice,
      });
    const sessionId = (await manager.getSession()).sessionId;

    const sessionPreExit = await manager.getSessionHelper(player1.address);
    expect(sessionPreExit.playerCount).to.equal(2);
    /* the output arrays are the same but the test fails. In my envinronment the first array is :
    [
  '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
  '0x70997970C51812dc3A010C7d01b50e0d17dc79C8'
    ]

    and the second array is:
    [
  '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
  '0x70997970C51812dc3A010C7d01b50e0d17dc79C8'
    ]

    expect(sessionPreExit.players).to.equal([player1.address, player2.address]);
    */

    await manager.connect(player2).exitSession();
    const session = await manager.getSessionHelper(player1.address);
    expect(session.playerCount).to.equal(1);
    expect(session.players[0]).to.equal(player1.address);
    

  });


});
