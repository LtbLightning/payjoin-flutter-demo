import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:payjoin_flutter/receive/v1.dart' as v1;
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/common.dart';

class PayjoinManager {
  late Wallet wallet;

  Future<Uri> buildPjUri(double amount, String pj) async {
    try {
      final pjUri =
          "tb1q5tsjcyz7xmet07yxtumakt739y53hcttmntajq?amount=${amount / 100000000.0}&pj=$pj";
      return Uri.parse(pjUri);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<PartiallySignedTransaction> buildOriginalPsbt(
      senderWallet, senderAddress, payjoinAmount) async {
    final txBuilder = TxBuilder();
    final address =
        await Address.fromString(s: senderAddress!, network: Network.testnet);
    final script = await address.scriptPubkey();

    final psbt = await txBuilder
        .addRecipient(script, payjoinAmount)
        .feeRate(2000.0)
        .finish(senderWallet);
    return psbt.$1;
  }

  Future<v1.UncheckedProposal> handlePjRequest(
      Request req, Headers headers) async {
    final proposal = await v1.UncheckedProposal.fromRequest(
        body: req.body.toList(),
        query: (await req.url.query())!,
        headers: headers);
    return proposal;
  }

  Future<v1.PayjoinProposal?> handleProposal(
      {required v1.UncheckedProposal proposal,
      required Wallet senderWallet,
      senderAddress}) async {
    try {
      final _ = await proposal.extractTxToScheduleBroadcast();
      final ownedInput = await proposal.checkBroadcastSuitability(
          canBroadcast: (i) => true); //TODO: Create real function
      final outputsOwned = await ownedInput.checkInputsNotOwned(
          isOwned: (i) => false); //TODO: Create real function using BDK
      //addressFromScript
      //wallet isMine
      final seenInput = await outputsOwned.checkNoMixedInputScripts();
      final outputsUnknown = (await seenInput.checkNoInputsSeenBefore(
          ptr: seenInput, isKnown: (i) => false)); //?ptr
      final payjoin = await outputsUnknown.checkNoInputsSeenBefore(
          //TODO: Rename this func
          isReceiverOutput: (i) => Future.value(true)); //?
      final availableInputs = await senderWallet.listUnspent();
      Map<int, types.OutPoint> candidateInputs = {
        for (var input in availableInputs)
          input.txout.value: types.OutPoint(
              txid: input.outpoint.txid.toString(), vout: input.outpoint.vout)
      };
      final selectedOutpoint =
          await payjoin.tryPreservingPrivacy(candidateInputs: candidateInputs);
      var selectedUtxo = availableInputs.firstWhere(
          (i) =>
              i.outpoint.txid.toString() == selectedOutpoint.txid &&
              i.outpoint.vout == selectedOutpoint.vout,
          orElse: () => throw Exception('UTXO not found'));
      var txoToContribute = types.TxOut(
        value: selectedUtxo.txout.value,
        scriptPubkey: selectedUtxo.txout.scriptPubkey.bytes,
      );

      var outpointToContribute = types.OutPoint(
        txid: selectedUtxo.outpoint.txid.toString(),
        vout: selectedUtxo.outpoint.vout,
      );
      payjoin.contributeWitnessInput(
          txo: txoToContribute, outpoint: outpointToContribute);
      payjoin.substituteOutputAddress(address: senderAddress!);

      var psbt; //?

      final payjoinProposal = await payjoin.finalizeProposal(processPsbt: psbt);
      senderWallet.sign(psbt: psbt);
      return payjoinProposal;
    } on Exception catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }

  Future performPayjoin() async {
    // final response = await handlePjRequest(req, headers);
  }
}
