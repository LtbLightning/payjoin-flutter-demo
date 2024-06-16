import 'dart:typed_data';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:payjoin_flutter/receive/v1.dart' as v1;
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/uri.dart' as uri;

class PayjoinManager {
  static const pjUrl = "https://localhost:8088";

  Future<String> buildPjStr(double amount, String address, {String? pj}) async {
    try {
      final pjUri =
          "bitcoin:$address?amount=${amount / 100000000.0}&pj=${pj ?? pjUrl}";
      debugPrint("pjUri: : $pjUri");
      return pjUri;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<uri.Uri> stringToUri(String pj) async {
    try {
      return await uri.Uri.fromString(pj);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  //Sender psbt
  Future<PartiallySignedTransaction> buildOriginalPsbt(
      senderWallet, uri.Uri pjUri, double feeRate) async {
    final txBuilder = TxBuilder();
    final address = await Address.fromString(
        s: await pjUri.address(), network: Network.regtest);
    final script = await address.scriptPubkey();
    int amount = (((await pjUri.amount()) ?? 0) * 100000000).toInt();
    final psbt = await txBuilder
        .addRecipient(script, amount)
        .feeRate(feeRate)
        .finish(senderWallet);
    return psbt.$1;
  }

  Future<String?> handlePjRequest(
      Request req, Headers headers, receiverWallet) async {
    final uncheckedProposal = await v1.UncheckedProposal.fromRequest(
        body: req.body.toList(),
        query: (await req.url.query())!,
        headers: headers);

    final proposal = await handleProposal(
        proposal: uncheckedProposal, receiverWallet: receiverWallet);

    return await proposal?.psbt();
  }

  Future<bool> isReceiverOutput(Uint8List bytes, Wallet wallet) async {
    return true;
  }

  Future<bool> isKnown(types.OutPoint outputScript, Wallet wallet) async {
    return false;
  }

  Future<bool> canBroadcast(Uint8List bytes, Wallet wallet) async {
    return true;
  }

  Future<bool> isOwned(Uint8List bytes, Wallet wallet) async {
    final script = ScriptBuf(bytes: bytes);
    return await wallet.isMine(script: script);
  }

  Future<String> processPsbt(String preProcessed, Wallet wallet) async {
    final psbt = await PartiallySignedTransaction.fromString(preProcessed);
    final isFinalized = await wallet.sign(
        psbt: psbt,
        signOptions: const SignOptions(
            multiSig: false,
            trustWitnessUtxo: true,
            allowAllSighashes: true,
            removePartialSigs: true,
            tryFinalize: true,
            signWithTapInternalKey: true,
            allowGrinding: true));
    if (isFinalized) {
      return await psbt.serialize();
    } else {
      throw Exception("The psbt can not finalized");
    }
  }

  Future<v1.PayjoinProposal?> handleProposal({
    required v1.UncheckedProposal proposal,
    required Wallet receiverWallet,
  }) async {
    try {
      final _ = await proposal.extractTxToScheduleBroadcast();
      final ownedInput = await proposal.checkBroadcastSuitability(
          canBroadcast: (i) => canBroadcast(i, receiverWallet));

      final outputsOwned = await ownedInput.checkInputsNotOwned(
          isOwned: (i) => isOwned(i, receiverWallet));

      final seenInput = await outputsOwned.checkNoMixedInputScripts();

      final outputsUnknown = (await seenInput.checkNoInputsSeenBefore(
          isKnown: (i) => isKnown(i, receiverWallet))); //?ptr
      final payjoin = await outputsUnknown.identifyReceiverOutputs(
        isReceiverOutput: (i) => isReceiverOutput(i, receiverWallet),
      );

      final availableInputs = await receiverWallet.listUnspent();
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
      final newReceiverAddress = await ((await receiverWallet.getAddress(
                  addressIndex: const AddressIndex.increase()))
              .address)
          .asString();
      payjoin.substituteOutputAddress(address: newReceiverAddress);
      final payjoinProposal = await payjoin.finalizeProposal(
          processPsbt: (i) => processPsbt(i, receiverWallet));
      return payjoinProposal;
    } on Exception catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }

  Future<Transaction> extractPjTx(
      Wallet senderWallet, String psbtString) async {
    final psbt = await PartiallySignedTransaction.fromString(psbtString);
    senderWallet.sign(psbt: psbt);
    var transaction = psbt.extractTx();
    return transaction;
  }

  Future<String> psbtToBase64String(PartiallySignedTransaction psbt) async {
    String bytes = await psbt.serialize();
    return bytes;
    // String base64String = base64Encode(bytes);
    // return base64String;
  }
}
