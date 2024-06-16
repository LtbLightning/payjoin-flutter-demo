import 'dart:convert';
import 'dart:io';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:bdk_flutter_demo/managers/payjoin_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/send.dart' as send;
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
  TextEditingController amountController = TextEditingController();
  TextEditingController pjUriController = TextEditingController();
  TextEditingController psbtController = TextEditingController();
  TextEditingController responseController = TextEditingController();
  bool isPayjoinEnabled = false;
  bool isReceiver = false;
  FeeRangeEnum? feeRange;
  PayjoinManager payjoinManager = PayjoinManager();
  dynamic pjUri;
  dynamic senderPsbt;
  dynamic requestContextV1;
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
          network: Network.regtest,
          mnemonic: mnemonic,
        );
        final descriptor = await Descriptor.newBip86(
            secretKey: descriptorSecretKey,
            network: Network.regtest,
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
    });
    return res;
  }

  Future<void> sendTx(String addressStr, int amount) async {
    try {
      final txBuilder = TxBuilder();
      final address =
          await Address.fromString(s: addressStr, network: Network.regtest);
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
    String esploraUrl =
        Platform.isAndroid ? 'http://10.0.2.2:30000' : 'http://127.0.0.1:30000';
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
  }

  Future<void> changePayjoin(bool value) async {
    setState(() {
      isPayjoinEnabled = value;
      //   displayText = uri.toString();
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
                              Network.regtest, "password", "m/84'/1'/0'");
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
                          text: requestContextV1 != null
                              ? "Finalize Payjoin"
                              : isPayjoinEnabled
                                  ? "Perform Payjoin"
                                  : "Send Bit",
                          callback: () async {
                            isPayjoinEnabled
                                ? performPayjoin()
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
      await sendTx(recipientAddress.text, int.parse(amountController.text));
    }
  }

  showPsbtBottomSheet(String psbt) {
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
        if (!isReceiver) ...[
          if (requestContextV1 != null)
            TextFieldContainer(
              child: TextFormField(
                controller: responseController,
                style: Theme.of(context).textTheme.bodyLarge,
                keyboardType: TextInputType.multiline,
                maxLines: 5,
                decoration: const InputDecoration(hintText: "Enter response"),
              ),
            )
          else ...[
            buildFields(),
            Center(
              child: TextButton(
                onPressed: () => chooseFeeRange(),
                child: const Text(
                  "Choose fee range",
                ),
              ),
            ),
          ]
        ] else ...[
          TextFieldContainer(
            child: TextFormField(
              controller: psbtController,
              style: Theme.of(context).textTheme.bodyLarge,
              keyboardType: TextInputType.multiline,
              maxLines: 5,
              decoration: const InputDecoration(hintText: "Enter psbt"),
            ),
          ),
          TextFieldContainer(
            child: TextFormField(
              controller: pjUriController,
              style: Theme.of(context).textTheme.bodyLarge,
              keyboardType: TextInputType.multiline,
              maxLines: 5,
              decoration: const InputDecoration(hintText: "Enter pjUri"),
            ),
          ),
        ]
      ],
    );
  }

  Future performPayjoin() async {
    if (!isReceiver && requestContextV1 == null) {
      await performSender();
    }
    if (isReceiver) {
      await performReceiver();
    }
    //Sender
    if (responseController.text.isNotEmpty) {
      String response = jsonDecode(responseController.text);
      final checkedPayjoinProposal = await requestContextV1.$2
          .processResponse(response: base64Decode(response));
      final transaction =
          await payjoinManager.extractPjTx(wallet, checkedPayjoinProposal);
      blockchain.broadcast(transaction: transaction);
    }
  }

  //Sender
  Future performSender() async {
    pjUri = await payjoinManager.buildPjUri(
      double.parse(amountController.text),
      recipientAddress.text,
    );
    senderPsbt = await payjoinManager.psbtToBase64String(
        await payjoinManager.buildOriginalPsbt(
            wallet, pjUri, feeRange?.feeValue ?? FeeRangeEnum.high.feeValue));
    showPsbtBottomSheet(senderPsbt);
    requestContextV1 = await (await (await send.RequestBuilder.fromPsbtAndUri(
                psbtBase64: senderPsbt, uri: pjUri))
            .buildWithAdditionalFee(
                maxFeeContribution: 1000,
                minFeeRate: 0,
                clampFeeContribution: false))
        .extractContextV1();
  }

  Future performReceiver() async {
    requestContextV1 = await (await (await send.RequestBuilder.fromPsbtAndUri(
                psbtBase64: psbtController.text,
                uri: await payjoinManager.stringToUri(pjUriController.text)))
            .buildWithAdditionalFee(
                maxFeeContribution: 1000,
                minFeeRate: 0,
                clampFeeContribution: false))
        .extractContextV1();
    final request = requestContextV1.$1;
    final headers = Headers(map: {
      'content-type': 'text/plain',
      'content-length': request.body.length.toString(),
    });
    String? response =
        await payjoinManager.handlePjRequest(request, headers, wallet);
    if (response == null) {
      return throw Exception("Response is null");
    }

    var responseBodyJson = requestContextV1.$1.toJson();
    showPsbtBottomSheet(responseBodyJson);
  }
}
//