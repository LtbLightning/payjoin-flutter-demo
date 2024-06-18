import 'dart:convert';
import 'dart:io';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:bdk_flutter_demo/managers/payjoin_manager.dart';
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
  String balance = "0";
  TextEditingController mnemonic = TextEditingController();
  TextEditingController recipientAddress = TextEditingController();
  TextEditingController amountController = TextEditingController();
  TextEditingController pjUriController = TextEditingController();
  TextEditingController psbtController = TextEditingController();
  TextEditingController receiverPsbtController = TextEditingController();
  bool _isPayjoinEnabled = false;
  bool isReceiver = false;
  FeeRangeEnum? feeRange;
  PayjoinManager payjoinManager = PayjoinManager();
  String pjUri = '';
  bool isRequestSent = false;

  String get getSubmitButtonTitle => _isPayjoinEnabled
      ? isRequestSent
          ? "Finalize Payjoin"
          : isReceiver
              ? pjUri.isNotEmpty
                  ? "Handle Request"
                  : "Build Pj Uri"
              : "Perform Payjoin"
      : "Send Bit";

  Future<void> generateMnemonicHandler() async {
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
          network: Network.signet,
          mnemonic: mnemonic,
        );
        final descriptor = await Descriptor.newBip86(
            secretKey: descriptorSecretKey,
            network: Network.signet,
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
    String mnemonic,
    Network network,
    String? password,
    String path, //TODO: Derived error: Address contains key path
  ) async {
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

  Future<void> getBalance() async {
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
      if (isReceiver && address != null) {
        recipientAddress.text = address!;
      }
    });
    return res;
  }

  Future<void> sendTx(String addressStr, int amount) async {
    try {
      final txBuilder = TxBuilder();
      final address =
          await Address.fromString(s: addressStr, network: Network.signet);
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

/* const BlockchainConfig.electrum(
              config: ElectrumConfig(
                  stopGap: 10,
                  timeout: 5,
                  retry: 5,
                  url: "ssl://electrum.blockstream.info:60002",
                  validateDomain: false)) */
  ///Step2:Client
  blockchainInit() async {
    String esploraUrl = 'https://mutinynet.ltbl.io/api';
    try {
      blockchain = await Blockchain.create(
          config: BlockchainConfig.esplora(
              config: EsploraConfig(baseUrl: esploraUrl, stopGap: 10)));
    } on Exception catch (e) {
      setState(() {
        displayText = "Error: ${e.toString()}";
      });
    }
  }

  Future<void> syncWallet() async {
    wallet.sync(blockchain: blockchain);
    await getBalance();
  }

  Future<void> changePayjoin(bool value) async {
    setState(() {
      _isPayjoinEnabled = value;
    });
  }

  Future<void> changeFrom(bool value) async {
    setState(() {
      isReceiver = value;
    });
  }

  Future<void> chooseFeeRange() async {
    feeRange = await showModalBottomSheet(
      context: context,
      builder: (context) => SelectFeeRange(feeRange: feeRange),
      constraints: const BoxConstraints.tightFor(height: 300),
    );
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
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              /* Balance */
              BalanceContainer(
                text: "$balance Sats",
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
                            Network.signet, "password", "m/84'/1'/0'");
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
                      CustomSwitchTile(
                        title: "Payjoin",
                        value: _isPayjoinEnabled,
                        onChanged: changePayjoin,
                      ),
                      _isPayjoinEnabled ? buildPayjoinFields() : buildFields(),
                      SubmitButton(
                        text: getSubmitButtonTitle,
                        callback: () async {
                          _isPayjoinEnabled
                              ? performPayjoin(formKey)
                              : await onSendBit(formKey);
                        },
                      )
                    ]),
              ))
            ],
          ),
        ));
  }

  onSendBit(formKey) async {
    if (formKey.currentState!.validate()) {
      await sendTx(recipientAddress.text, int.parse(amountController.text));
    }
  }

  showBottomSheet(String value) {
    return showModalBottomSheet(
      useSafeArea: true,
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
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
            controller: amountController,
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

  Widget buildPayjoinFields() {
    return Column(
      children: [
        CustomSwitchTile(
            title: isReceiver ? "Receiver" : "Sender",
            value: isReceiver,
            onChanged: changeFrom),
        if (isReceiver) ...[
          buildReceiverFields(),
        ] else
          ...buildSenderFields()
      ],
    );
  }

  List<Widget> buildSenderFields() {
    if (isRequestSent) {
      return [
        TextFieldContainer(
          child: TextFormField(
            controller: receiverPsbtController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter the receiver psbt';
              }
              return null;
            },
            style: Theme.of(context).textTheme.bodyLarge,
            keyboardType: TextInputType.multiline,
            maxLines: 5,
            decoration: const InputDecoration(hintText: "Enter receiver psbt"),
          ),
        )
      ];
    } else {
      return [
        TextFieldContainer(
          child: TextFormField(
            controller: pjUriController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter the pjUri';
              }
              return null;
            },
            style: Theme.of(context).textTheme.bodyLarge,
            keyboardType: TextInputType.multiline,
            maxLines: 5,
            decoration: const InputDecoration(hintText: "Enter pjUri"),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => chooseFeeRange(),
            child: const Text(
              "Choose fee range",
            ),
          ),
        ),
      ];
    }
  }

  Widget buildReceiverFields() {
    return pjUri.isEmpty
        ? buildFields()
        : TextFieldContainer(
            child: TextFormField(
              controller: psbtController,
              style: Theme.of(context).textTheme.bodyLarge,
              keyboardType: TextInputType.multiline,
              maxLines: 5,
              decoration: const InputDecoration(hintText: "Enter psbt"),
            ),
          );
  }

  Future performPayjoin(formKey) async {
    if (formKey.currentState!.validate()) {
      if (isReceiver) {
        await performReceiver();
      } else {
        await performSender();
      }
    }
  }

  //Sender
  Future performSender() async {
    if (!isRequestSent) {
      String senderPsbt = await payjoinManager.psbtToBase64String(
          await payjoinManager.buildOriginalPsbt(
              wallet,
              await payjoinManager.stringToUri(pjUriController.text),
              feeRange?.feeValue ?? FeeRangeEnum.high.feeValue));
      showBottomSheet(senderPsbt);

      setState(() {
        isRequestSent = true;
      });
    } // Finalize payjoin
    else {
      String receiverPsbt = receiverPsbtController.text;
      final transaction =
          await payjoinManager.extractPjTx(wallet, receiverPsbt);
      blockchain.broadcast(transaction: transaction);
    }
  }

  //Receiver
  Future performReceiver() async {
    if (pjUri.isEmpty) {
      buildReceiverPjUri();
    } else {
      final (String? receiverPsbt, contextV1) = await payjoinManager
          .handlePjRequest(psbtController.text, pjUri, wallet);
      if (receiverPsbt == null) {
        return throw Exception("Response is null");
      }
      final checkedPayjoinProposal =
          await contextV1.processResponse(response: utf8.encode(receiverPsbt));
      showBottomSheet(checkedPayjoinProposal);
    }
  }

  Future<void> buildReceiverPjUri() async {
    String pjStr = await payjoinManager.buildPjStr(
      double.parse(amountController.text),
      recipientAddress.text,
    );

    setState(() {
      displayText = pjStr;
      pjUri = pjStr;
    });
  }
}
