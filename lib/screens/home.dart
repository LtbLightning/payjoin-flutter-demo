import 'package:bdk_flutter/bdk_flutter.dart' as bdk;
import 'package:bdk_flutter_demo/managers/payjoin_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/receive/v2.dart' as v2;
import 'package:payjoin_flutter/send.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/widgets.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late bdk.Wallet wallet;
  late bdk.Blockchain blockchain;
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
  bool isV2 = true;
  v2.ActiveSession? v2Session;
  RequestContext? reqCtx;
  v2.UncheckedProposal? uncheckedProposal;
  v2.PayjoinProposal? payjoinProposal;
  FeeRangeEnum? feeRange;
  PayjoinManager payjoinManager = PayjoinManager();
  String pjUri = '';

  String get getSubmitButtonTitle => _isPayjoinEnabled
      ? reqCtx != null
          ? "Finalize Payjoin"
          : isReceiver
              ? pjUri.isNotEmpty
                  ? "Handle Request"
                  : "Build Pj Uri"
              : "Perform Payjoin"
      : "Send Bit";

  Future<void> generateMnemonicHandler() async {
    var res = (await bdk.Mnemonic.create(bdk.WordCount.words12)).asString();

    setState(() {
      mnemonic.text = res;
      displayText = res;
    });
  }

  Future<List<bdk.Descriptor>> getDescriptors(String mnemonicStr) async {
    final descriptors = <bdk.Descriptor>[];
    try {
      for (var e in [
        bdk.KeychainKind.externalChain,
        bdk.KeychainKind.internalChain
      ]) {
        final mnemonic = await bdk.Mnemonic.fromString(mnemonicStr);
        final descriptorSecretKey = await bdk.DescriptorSecretKey.create(
          network: bdk.Network.signet,
          mnemonic: mnemonic,
        );
        final descriptor = await bdk.Descriptor.newBip86(
            secretKey: descriptorSecretKey,
            network: bdk.Network.signet,
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
    bdk.Network network,
    String? password,
    String path, //TODO: Derived error: Address contains key path
  ) async {
    try {
      final descriptors = await getDescriptors(mnemonic);
      await blockchainInit();
      final res = await bdk.Wallet.create(
          descriptor: descriptors[0],
          changeDescriptor: descriptors[1],
          network: network,
          databaseConfig: const bdk.DatabaseConfig.memory());
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
    final balanceObj = wallet.getBalance();
    final res = "Total Balance: ${balanceObj.total.toString()}";
    if (kDebugMode) {
      print(res);
    }
    setState(() {
      balance = balanceObj.total.toString();
      displayText = res;
    });
  }

  Future<bdk.AddressInfo> getNewAddress() async {
    final res = await wallet.getAddress(
        addressIndex: const bdk.AddressIndex.increase());
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
      final txBuilder = bdk.TxBuilder();
      final address = await bdk.Address.fromString(
          s: addressStr, network: bdk.Network.signet);
      final script = await address.scriptPubkey();

      final psbt = await txBuilder
          .addRecipient(script, BigInt.from(amount))
          .feeRate(1.0)
          .finish(wallet);

      final isFinalized = await wallet.sign(psbt: psbt.$1);
      if (isFinalized) {
        final tx = psbt.$1.extractTx();
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
    String esploraUrl = 'https://mutinynet.com/api';
    try {
      blockchain = await bdk.Blockchain.create(
          config: bdk.BlockchainConfig.esplora(
              config: bdk.EsploraConfig(
                  baseUrl: esploraUrl, stopGap: BigInt.from(10))));
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
    // Reset the payjoin state when disabling it.
    // This is useful to start a new payjoin session by toggling the switch.
    if (!value) {
      resetPayjoinSession();
    }
  }

  Future<void> changeV2(bool value) async {
    setState(() {
      isV2 = value;
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
                            bdk.Network.signet, "password", "m/84'/1'/0'");
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
                      v2Session == null && reqCtx == null
                          ? SubmitButton(
                              text: getSubmitButtonTitle,
                              callback: () async {
                                _isPayjoinEnabled
                                    ? performPayjoin(formKey)
                                    : await onSendBit(formKey);
                              },
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    v2Session != null
                                        ? payjoinProposal != null
                                            ? 'Proposal sent, waiting for tx...'
                                            : uncheckedProposal != null
                                                ? 'Received request, adding inputs to proposal...'
                                                : 'Session initiated, waiting for request...'
                                        : 'Request sent, waiting for proposal to finalize tx...',
                                  ),
                                ),
                              ],
                            ),
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

  showBottomSheet(
    String text, {
    String? toCopy,
    String? toUrl,
  }) {
    return showModalBottomSheet(
      useSafeArea: true,
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            if (toCopy != null && toCopy.isNotEmpty)
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: toCopy));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Copied to clipboard!'),
                  ));
                },
                icon: const Icon(
                  Icons.copy,
                  size: 36,
                ),
              ),
            if (toUrl != null && toUrl.isNotEmpty)
              IconButton(
                onPressed: () {
                  launchUrl(Uri.parse(toUrl));
                },
                icon: const Icon(
                  Icons.open_in_browser,
                  size: 36,
                ),
              ),
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
          title: isV2 ? "v2" : "v1",
          value: isV2,
          onChanged: changeV2,
        ),
        CustomSwitchTile(
          title: isReceiver ? "Receiver" : "Sender",
          value: isReceiver,
          onChanged: changeFrom,
        ),
        if (isReceiver) ...[
          buildReceiverFields(),
        ] else
          ...buildSenderFields()
      ],
    );
  }

  List<Widget> buildSenderFields() {
    if (reqCtx == null) {
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
    } else {
      if (!isV2) {
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
              decoration:
                  const InputDecoration(hintText: "Enter receiver psbt"),
            ),
          )
        ];
      }
      return [];
    }
  }

  Widget buildReceiverFields() {
    return pjUri.isEmpty
        ? buildFields()
        : isV2
            ? Container()
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
    if (isV2) {
      // Build payjoin request with original psbt and send it to the
      //  payjoin directory where the receiver can poll it
      final pjUri = await payjoinManager.stringToUri(pjUriController.text);
      final originalPsbt = await payjoinManager.buildOriginalPsbt(
        wallet,
        pjUri,
        feeRange?.feeValue ?? FeeRangeEnum.high.feeValue,
      );
      final request = await payjoinManager.buildPayjoinRequest(
        originalPsbt,
        pjUri,
        feeRange?.feeValue ?? FeeRangeEnum.high.feeValue,
      );
      setState(() {
        reqCtx = request;
      });

      // Request and keep polling the payjoin directoy for the proposal
      //  from the receiver
      String psbt = originalPsbt;
      try {
        psbt = await payjoinManager.requestAndPollV2Proposal(
          reqCtx!,
        );
        debugPrint('Receiver proposed payjoin PSBT: $psbt');
      } catch (e) {
        // No proposal received, make a normal tx with the original psbt
        debugPrint('No proposal received, broadcasting original tx');
      }

      // If a proposal is received, finalize the payjoin
      final transaction = await payjoinManager.extractPjTx(wallet, psbt);
      final txId = await blockchain.broadcast(transaction: transaction);
      debugPrint('Broacasted tx: $txId');
      resetPayjoinSession();

      showBottomSheet(
        '${psbt == originalPsbt ? 'Original tx with id' : 'Payjoin tx with id'} '
        '$txId broadcasted!',
        toCopy: txId,
        toUrl: 'https://mutinynet.com/tx/$txId',
      );
    } else {
      // Build V1 payjoin request with original psbt
      if (reqCtx == null) {
        final pjUri = await payjoinManager.stringToUri(pjUriController.text);
        final originalPsbt = await payjoinManager.buildOriginalPsbt(
          wallet,
          pjUri,
          feeRange?.feeValue ?? FeeRangeEnum.high.feeValue,
        );
        final request = await payjoinManager.buildPayjoinRequest(
          originalPsbt,
          pjUri,
          feeRange?.feeValue ?? FeeRangeEnum.high.feeValue,
        );
        debugPrint('Original Sender PSBT: $originalPsbt');

        setState(() {
          reqCtx = request;
        });
        showBottomSheet(originalPsbt, toCopy: originalPsbt);
      } else {
        // Finalize payjoin
        final proposalPsbt = receiverPsbtController.text;
        debugPrint('Receiver proposed PSBT: $proposalPsbt');
        final checkedProposal =
            await payjoinManager.processV1Proposal(reqCtx!, proposalPsbt);

        final transaction =
            await payjoinManager.extractPjTx(wallet, checkedProposal);
        String? txId;
        try {
          txId = await blockchain.broadcast(transaction: transaction);
          debugPrint('TxId: $txId');
        } catch (e) {
          debugPrint('Error broadcasting tx: $e');
        }

        resetPayjoinSession();

        if (txId != null) {
          showBottomSheet(
            txId,
            toCopy: txId,
            toUrl: 'https://mutinynet.com/tx/$txId',
          );
        } else {
          showBottomSheet('Error broadcasting tx');
        }
      }
    }
  }

  //Receiver
  Future performReceiver() async {
    // Create a new payjoin uri (and session if v2)
    try {
      if (isV2) {
        // Start a payjoin session and create a new payjoin uri
        await initReceiverSession();

        // Poll for requests made by the sender to this payjoin uri
        final requestProposal = await payjoinManager.pollV2Request(v2Session!);
        setState(() {
          uncheckedProposal = requestProposal;
        });

        // Handle the request and send back the payjoin proposal
        final (originalTx, proposedPayjoin) =
            await payjoinManager.handleV2Request(requestProposal, wallet);
        setState(() {
          payjoinProposal = proposedPayjoin;
        });
        // Wait some time for the tx to be broadcasted
        await Future.delayed(const Duration(seconds: 3));

        // Wait for the original or payjoin tx to be broadcasted
        final proposalTxId =
            await payjoinManager.getTxIdFromPsbt(await proposedPayjoin.psbt());
        final receivedTxId = await waitForTransaction(
          originalTxId: await originalTx.txid(),
          proposalTxId: proposalTxId,
        );
        resetPayjoinSession();

        if (receivedTxId.isNotEmpty) {
          showBottomSheet(
            '${receivedTxId == proposalTxId ? 'Payjoin' : 'Original'} tx received!',
          );
        }
      } else {
        if (pjUri.isEmpty) {
          await initReceiverSession();
        } else {
          // Handle payjoin request and send back the payjoin proposal
          final proposalPsbt =
              await payjoinManager.handleV1Request(psbtController.text, wallet);
          if (proposalPsbt == null) {
            return throw Exception("Response is null");
          }
          resetPayjoinSession();
          showBottomSheet(proposalPsbt, toCopy: proposalPsbt);
        }
      }
    } catch (e) {
      debugPrint(e.toString());
      if (e is PayjoinException) {
        // In a real app you would handle the error better
        debugPrint(e.toString());
        showBottomSheet('PayJoin error: ${e.message}');
        resetPayjoinSession();
      }
    }
  }

  Future<void> initReceiverSession() async {
    String pjStr;
    final amount = int.parse(amountController.text);
    if (isV2) {
      v2.ActiveSession session;
      (pjStr, session) = await payjoinManager.buildV2PjStr(
        amount: amount,
        address: recipientAddress.text,
        network: Network.signet,
        expireAfter: 60 * 5, // 5 minutes
      );

      setState(() {
        v2Session = session;
      });
    } else {
      pjStr = await payjoinManager.buildV1PjStr(
        amount,
        recipientAddress.text,
      );
    }

    setState(() {
      displayText = pjStr;
      pjUri = pjStr;
    });
  }

  Future<String> waitForTransaction({
    required String originalTxId,
    required String proposalTxId,
    int timeout = 1,
  }) async {
    debugPrint('Waiting for payjoin tx to be sent...');
    await syncWallet();
    final txs = wallet.listTransactions(includeRaw: false);
    try {
      final tx = txs.firstWhere(
          (tx) => tx.txid == originalTxId || tx.txid == proposalTxId);
      debugPrint('Tx found: ${tx.txid}');
      return tx.txid;
    } catch (e) {
      debugPrint('Tx not found, retrying after $timeout second(s)...');
      if (reqCtx == null) {
        // The session was canceled, stop polling
        return '';
      }
      await Future.delayed(Duration(seconds: timeout));
      return waitForTransaction(
        originalTxId: originalTxId,
        proposalTxId: proposalTxId,
      );
    }
  }

  void resetPayjoinSession() {
    setState(() {
      pjUri = '';
      v2Session = null;
      reqCtx = null;
      uncheckedProposal = null;
      payjoinProposal = null;
    });
    // Also clean the text controllers to start a new payjoin session
    recipientAddress.clear();
    amountController.clear();
    pjUriController.clear();
    receiverPsbtController.clear();
    psbtController.clear();
  }
}
