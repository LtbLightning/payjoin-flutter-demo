import 'dart:convert';
import 'dart:io';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../managers/bdk_manager.dart';
import '../managers/payjoin_manager.dart';
import '../widgets/widgets.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

//cart super leaf clinic pistol plug replace close super tooth wealth usage
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
  PayJoinManager payjoinManager = PayJoinManager();
  BdkManager bdkManager = BdkManager();
  dynamic pjUri;
  bool isRequestSent = false;

  String get getSubmitButtonTitle => _isPayjoinEnabled
      ? isRequestSent
          ? "Finalize Payjoin"
          : isReceiver
              ? pjUri != null
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

  createOrRestoreWallet(
    String mnemonic,
    Network network, {
    String? password,
  }) async {
    try {
      wallet =
          await bdkManager.createOrRestoreWallet(mnemonic, network, password);
      await getNewAddress();
      String esploraUrl = Platform.isAndroid
          ? 'http://10.0.2.2:30000'
          : 'http://127.0.0.1:30000';
      blockchain = await bdkManager.blockchainInit(esploraUrl);
      setState(() {
        displayText = "Wallet created successfully\n address: $address";
      });
    } on Exception catch (e) {
      setState(() {
        displayText = "Error: ${e.toString()}";
      });
    }
  }

  getNewAddress() async {
    final res = address =
        await (await bdkManager.getNewAddress(wallet)).address.asString();
    if (kDebugMode) {
      print(res);
    }
    setState(() {
      displayText = address;
      if (isReceiver && address != null) {
        recipientAddress.text = address!;
      }
    });
    return res;
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

  Future<void> sendTx(String addressStr, int amount) async {
    try {
      final psbt = await bdkManager.buildPsbt(wallet, addressStr, amount, 5);

      final res = bdkManager.signPsbt(await psbt.serialize(), wallet);
      if (res != null) {
        final tx = await psbt.extractTx();
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

  Future<void> syncWallet() async {
    wallet.sync(blockchain: blockchain);
    await getBalance();
  }

  Future<void> changePayJoin(bool value) async {
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
                        await createOrRestoreWallet(
                            mnemonic.text, Network.regtest);
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
                        onChanged: changePayJoin,
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
    return pjUri == null
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
    try {
      if (!isRequestSent) {
        String senderPsbt = await (await bdkManager.buildPsbt(
                wallet,
                await (await payjoinManager.stringToUri(pjUriController.text))
                    .address(),
                (((await (await payjoinManager
                                    .stringToUri(pjUriController.text))
                                .amount()) ??
                            0) *
                        100000000)
                    .toInt(),
                feeRange?.feeValue ?? FeeRangeEnum.high.feeValue))
            .serialize();
        showBottomSheet(senderPsbt);

        setState(() {
          isRequestSent = true;
        });
      } // Finalize payjoin
      else {
        String receiverPsbt = receiverPsbtController.text;
        final transaction =
            await bdkManager.extractTxFromPsbtString(wallet, receiverPsbt);
        final txid = await blockchain.broadcast(transaction: transaction);
        setState(() {
          displayText = "PayJoin transaction successfully completed: $txid";
        });
      }
    } on Exception catch (e) {}
  }

  //Receiver
  Future performReceiver() async {
    if (pjUri == null) {
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
    payjoinManager.stringToUri(pjStr).then((value) {
      setState(() {
        displayText = pjStr;
        pjUri = value;
      });
    });
  }
}
