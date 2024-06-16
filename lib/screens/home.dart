import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/widgets.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late Wallet wallet;
  late Blockchain blockchain;
  String? displayText;
  String? address;
  String? balance;
  TextEditingController mnemonic = TextEditingController();
  TextEditingController recipientAddress = TextEditingController();
  TextEditingController amount = TextEditingController();
  bool isPayjoinEnabled = false;
  bool isReceiver = false;
  FeeRangeEnum feeRange = FeeRangeEnum.high;
  generateMnemonicHandler() async {
    var res = await (await Mnemonic.create(WordCount.words12)).asString();

    setState(() {
      mnemonic.text = res;
      displayText = res;
    });
  }

  Future<List<Descriptor>> getDescriptors(String mnemonicStr) async {
    final descriptors = <Descriptor>[];
    try {
      for (var e in [KeychainKind.externalChain, KeychainKind.internalChain]) {
        final mnemonic = await Mnemonic.fromString(mnemonicStr);
        final descriptorSecretKey = await DescriptorSecretKey.create(
          network: Network.testnet,
          mnemonic: mnemonic,
        );
        final descriptor = await Descriptor.newBip86(
            secretKey: descriptorSecretKey,
            network: Network.testnet,
            keychain: e);
        descriptors.add(descriptor);
      }
      return descriptors;
    } on Exception catch (e) {
      setState(() {
        displayText = "Error : ${e.toString()}";
      });
      rethrow;
    }
  }

  createOrRestoreWallet(
      String mnemonic, Network network, String? password, String path) async {
    try {
      final descriptors = await getDescriptors(mnemonic);
      await blockchainInit();
      final res = await Wallet.create(
          descriptor: descriptors[0],
          changeDescriptor: descriptors[1],
          network: network,
          databaseConfig: const DatabaseConfig.memory());
      setState(() {
        wallet = res;
      });
      var addressInfo = await getNewAddress();
      address = await addressInfo.address.asString();
      setState(() {
        displayText = "Wallet Created: $address";
      });
    } on Exception catch (e) {
      setState(() {
        displayText = "Error: ${e.toString()}";
      });
    }
  }

  getBalance() async {
    final balanceObj = await wallet.getBalance();
    final res = "Total Balance: ${balanceObj.total.toString()}";
    if (kDebugMode) {
      print(res);
    }
    setState(() {
      balance = balanceObj.total.toString();
      displayText = res;
    });
  }

  Future<AddressInfo> getNewAddress() async {
    final res =
        await wallet.getAddress(addressIndex: const AddressIndex.increase());
    if (kDebugMode) {
      print(res.address);
    }
    address = await res.address.asString();
    setState(() {
      displayText = address;
    });
    return res;
  }

  sendTx(String addressStr, int amount) async {
    try {
      final txBuilder = TxBuilder();
      final address =
          await Address.fromString(s: addressStr, network: Network.testnet);
      final script = await address.scriptPubkey();

      final psbt = await txBuilder
          .addRecipient(script, amount)
          .feeRate(1.0)
          .finish(wallet);

      final isFinalized = await wallet.sign(psbt: psbt.$1);
      if (isFinalized) {
        final tx = await psbt.$1.extractTx();
        final res = await blockchain.broadcast(transaction: tx);
        debugPrint(res);
      } else {
        debugPrint("psbt not finalized!");
      }

      setState(() {
        displayText = "Successfully broadcast $amount Sats to $addressStr";
      });
    } on Exception catch (e) {
      setState(() {
        displayText = "Error: ${e.toString()}";
      });
    }
  }

  blockchainInit() async {
    try {
      blockchain = await Blockchain.create(
          config: const BlockchainConfig.electrum(
              config: ElectrumConfig(
                  stopGap: 10,
                  timeout: 5,
                  retry: 5,
                  url: "ssl://electrum.blockstream.info:60002",
                  validateDomain: false)));
    } on Exception catch (e) {
      setState(() {
        displayText = "Error: ${e.toString()}";
      });
    }
  }

  syncWallet() async {
    wallet.sync(blockchain: blockchain);
  }

  changePayjoin(bool value) async {
    final uri =
        buildPjUri(10000000, "https://testnet.demo.btcpayserver.org/BTC/pj");

    setState(() {
      isPayjoinEnabled = value;
      displayText = uri.toString();
    });
  }

  changeFrom(bool value) async {
    setState(() {
      isReceiver = value;
    });
  }

  chooseFeeRange() async {
    feeRange = await showModalBottomSheet(
      context: context,
      builder: (context) => const SelectFeeRange(),
      constraints: const BoxConstraints.tightFor(height: 300),
    );
  }

  Uri buildPjUri(double amount, String pj) {
    try {
      final pjUri =
          "tb1q5tsjcyz7xmet07yxtumakt739y53hcttmntajq?amount=${amount / 100000000.0}&pj=$pj";
      return Uri.dataFromString(pjUri);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    return Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        /* Header */
        appBar: buildAppBar(context),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
            child: Column(
              children: [
                /* Balance */
                BalanceContainer(
                  text: "${balance ?? "0"} Sats",
                ),
                /* Result */
                ResponseContainer(
                  text: displayText ?? " ",
                ),
                StyledContainer(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                      SubmitButton(
                          text: "Generate Mnemonic",
                          callback: () async {
                            await generateMnemonicHandler();
                          }),
                      TextFieldContainer(
                        child: TextFormField(
                            controller: mnemonic,
                            style: Theme.of(context).textTheme.bodyLarge,
                            keyboardType: TextInputType.multiline,
                            maxLines: 5,
                            decoration: const InputDecoration(
                                hintText: "Enter your mnemonic")),
                      ),
                      SubmitButton(
                        text: "Create Wallet",
                        callback: () async {
                          await createOrRestoreWallet(mnemonic.text,
                              Network.testnet, "password", "m/84'/1'/0'");
                        },
                      ),
                      SubmitButton(
                        text: "Sync Wallet",
                        callback: () async {
                          await syncWallet();
                        },
                      ),
                      SubmitButton(
                        callback: () async {
                          await getBalance();
                        },
                        text: "Get Balance",
                      ),
                      SubmitButton(
                          callback: () async {
                            await getNewAddress();
                          },
                          text: "Get Address"),
                    ])),
                /* Send Transaction */
                StyledContainer(
                    child: Form(
                  key: formKey,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        buildPayjoinSwitch(),
                        if (isPayjoinEnabled) ...[
                          buildPayjoinFields(),
                        ] else ...[
                          buildFields()
                        ],
                        SubmitButton(
                          text:
                              isPayjoinEnabled ? "Perform Payjoin" : "Send Bit",
                          callback: () async {
                            isPayjoinEnabled
                                ? onPerformPayjoin()
                                : await onSendBit(formKey);
                          },
                        )
                      ]),
                ))
              ],
            ),
          ),
        ));
  }

  onSendBit(formKey) async {
    if (formKey.currentState!.validate()) {
      await sendTx(recipientAddress.text, int.parse(amount.text));
    }
  }

  onPerformPayjoin() {
    String psbt =
        """cHNidP8BAFUCAAAAASeaIyOl37UfxF8iD6WLD8E+HjNCeSqF1+Ns1jM7XLw5AAAAAAD/////AaBa6gsAAAAAGXapFP/pwAYQl8w7Y28ssEYPpPxCfStFiKwAAAAAAAEBIJVe6gsAAAAAF6kUY0UgD2jRieGtwN8cTRbqjxTA2+uHIgIDsTQcy6doO2r08SOM1ul+cWfVafrEfx5I1HVBhENVvUZGMEMCIAQktY7/qqaU4VWepck7v9SokGQiQFXN8HC2dxRpRC0HAh9cjrD+plFtYLisszrWTt5g6Hhb+zqpS5m9+GFR25qaAQEEIgAgdx/RitRZZm3Unz1WTj28QvTIR3TjYK2haBao7UiNVoEBBUdSIQOxNBzLp2g7avTxI4zW6X5xZ9Vp+sR/HkjUdUGEQ1W9RiED3lXR4drIBeP4pYwfv5uUwC89uq/hJ/78pJlfJvggg71SriIGA7E0HMunaDtq9PEjjNbpfnFn1Wn6xH8eSNR1""";
    return showModalBottomSheet(
      useSafeArea: true,
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(child: Text(psbt)),
            IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: psbt));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Copied to clipboard!'),
                  ));
                },
                icon: const Icon(
                  Icons.copy,
                  size: 36,
                ))
          ],
        ),
      ),
      //  constraints: const BoxConstraints.tightFor(height: 300),
    );
  }

  Widget buildFields() {
    return Column(
      children: [
        TextFieldContainer(
          child: TextFormField(
            controller: recipientAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your address';
              }
              return null;
            },
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: "Enter Address",
            ),
          ),
        ),
        TextFieldContainer(
          child: TextFormField(
            controller: amount,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter the amount';
              }
              return null;
            },
            keyboardType: TextInputType.number,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: "Enter Amount",
            ),
          ),
        ),
      ],
    );
  }

  Widget buildPayjoinSwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Payjoin",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Switch(
            value: isPayjoinEnabled,
            onChanged: changePayjoin,
          ),
        ),
      ],
    );
  }

  Widget buildPayjoinFields() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isReceiver ? "Receiver" : "Sender",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Switch(
                value: isReceiver,
                onChanged: changeFrom,
              ),
            ),
          ],
        ),
        if (isReceiver) ...[
          buildFields()
        ] else ...[
          Center(
            child: TextButton(
              onPressed: () => chooseFeeRange(),
              child: const Text(
                "Choose fee range",
              ),
            ),
          ),
        ]
      ],
    );
  }
}
