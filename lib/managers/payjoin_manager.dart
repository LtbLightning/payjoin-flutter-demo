import 'dart:convert';
import 'dart:typed_data';

import 'package:bdk_flutter/bdk_flutter.dart' as bdk;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:payjoin_flutter/receive/v1.dart' as v1;
import 'package:payjoin_flutter/receive/v2.dart' as v2;
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/uri.dart' as pj_uri;
import 'package:payjoin_flutter/send.dart' as send;

class PayjoinManager {
  static const pjUrl = "https://localhost:8088";
  static const ohttpRelay = "https://pj.bobspacebkk.com";
  static const payjoinDirectory = "https://payjo.in";
  static const v1ContentType = "text/plain";
  static const v2ContentType = "message/ohttp-req";

  Future<String> buildV1PjStr(
    int amount,
    String address, {
    String? pj,
  }) async {
    try {
      final pjUri =
          "bitcoin:$address?amount=${amount / 100000000}&pj=${pj ?? pjUrl}";
      debugPrint("pjUri: : $pjUri");
      return pjUri;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<(String, v2.ActiveSession)> buildV2PjStr({
    int? amount,
    required String address,
    required Network network,
    required int expireAfter,
  }) async {
    final session = await _startV2ReceiveSession(
      address: address,
      network: network,
      expireAfter: expireAfter,
    );
    String pjUriStr;
    final pjUriBuilder = session.pjUriBuilder();
    if (amount != null) {
      final pjUriBuilderWithAmount =
          pjUriBuilder.amount(amount: BigInt.from(amount));
      final pjUri = pjUriBuilderWithAmount.build();
      pjUriStr = pjUri.asString();
    } else {
      final pjUri = pjUriBuilder.build();
      pjUriStr = pjUri.asString();
    }

    return (pjUriStr, session);
  }

  Future<pj_uri.Uri> stringToUri(String pj) async {
    try {
      return await pj_uri.Uri.fromStr(pj);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<String> buildOriginalPsbt(
    bdk.Wallet senderWallet,
    pj_uri.Uri pjUri,
    int fee,
  ) async {
    final txBuilder = bdk.TxBuilder();
    final address = await bdk.Address.fromString(
        s: pjUri.address(), network: bdk.Network.signet);
    final script = address.scriptPubkey();
    double uriAmount = pjUri.amount() ?? 0;
    int amountSat = (uriAmount * 100000000.0).round();
    final (psbt, _) = await txBuilder
        .addRecipient(script, BigInt.from(amountSat))
        .feeAbsolute(BigInt.from(fee))
        .finish(senderWallet);
    await senderWallet.sign(
      psbt: psbt,
      signOptions: const bdk.SignOptions(
        trustWitnessUtxo: true,
        allowAllSighashes: false,
        removePartialSigs: true,
        tryFinalize: true,
        signWithTapInternalKey: true,
        allowGrinding: false,
      ),
    );

    final psbtBase64 = psbt.asString();
    debugPrint('Original Sender Psbt for request: $psbtBase64');
    return psbtBase64;
  }

  Future<send.RequestContext> buildPayjoinRequest(
    String originalPsbt,
    pj_uri.Uri pjUri,
    int fee,
  ) async {
    final requestBuilder = await send.RequestBuilder.fromPsbtAndUri(
        psbtBase64: originalPsbt, pjUri: pjUri.checkPjSupported());
    final requestContext =
        await requestBuilder.buildRecommended(minFeeRate: BigInt.from(1));

    return requestContext;
  }

  Future<String> requestAndPollV2Proposal(
    send.RequestContext requestContext,
  ) async {
    while (true) {
      debugPrint('Polling for V2 Proposal...');
      try {
        // Extract the request and context, keep repeating this too instead of
        //  only the post to get the timeout error
        final (request, ctx) = await requestContext.extractV2(
          ohttpProxyUrl: await pj_uri.Url.fromStr(payjoinDirectory),
        );

        // Post the request to the server
        final response = await http.post(
          Uri.parse(request.url.asString()),
          headers: {
            'Content-Type': v2ContentType,
          },
          body: request.body,
        );

        // Process the server response
        final checkedPayjoinProposal =
            await ctx.processResponse(response: response.bodyBytes);

        // If a valid proposal is received, return it
        if (checkedPayjoinProposal != null) {
          debugPrint('Received V2 proposal: $checkedPayjoinProposal');
          return checkedPayjoinProposal;
        }

        debugPrint('No valid proposal received, retrying after 2 seconds...');

        // Add a delay to avoid spamming the server with requests
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        // If the session times out or another error occurs, rethrow the error
        rethrow;
      }
    }
  }

  Future<String?> handleV1Request(
    String psbtBase64,
    bdk.Wallet receiverWallet,
  ) async {
    // Normally the request with the original psbt as body, a query and headers is received
    //  by listening to a server, but we only pass the original psbt here and
    //  add the headers and a mock query ourselves.
    final List<int> body = utf8.encode(psbtBase64);

    Map<String, String> headersMap = {
      'content-type': 'text/plain',
      'content-length': body.length.toString(),
    };
    final uncheckedProposal = await v1.UncheckedProposal.fromRequest(
      body: body.toList(),
      query: '',
      headers: Headers(map: headersMap),
    );

    final proposal = await _handleV1Proposal(
        proposal: uncheckedProposal, receiverWallet: receiverWallet);

    return proposal.psbt();
  }

  Future<v2.UncheckedProposal> pollV2Request(
    v2.ActiveSession session,
  ) async {
    while (true) {
      debugPrint('Polling for V2 Request...');
      try {
        // Extract the request and context, keep repeating this too instead of
        //  only the post to get the timeout error
        final (originalReq, originalCtx) = await session.extractReq();

        // Post the request to the server
        final originalPsbt = await http.post(
          Uri.parse(originalReq.url.asString()),
          body: originalReq.body,
          headers: {
            'Content-Type': v2ContentType,
          },
        );

        // Process the server response
        final uncheckedProposal = await session.processRes(
          body: originalPsbt.bodyBytes,
          ctx: originalCtx,
        );

        // If a valid unchecked proposal is received, return it
        if (uncheckedProposal != null) {
          debugPrint('Received V2 request: $uncheckedProposal');
          return uncheckedProposal;
        }

        debugPrint('No valid proposal received, retrying after 2 seconds...');

        // Add a delay to avoid spamming the server with requests
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        // If the session times out or another error occurs, rethrow the error
        rethrow;
      }
    }
  }

  Future<(bdk.Transaction originalTx, v2.PayjoinProposal)> handleV2Request(
    v2.UncheckedProposal uncheckedProposal,
    bdk.Wallet receiverWallet,
  ) async {
    final (originalTx, payjoinProposal) = await _handleV2Request(
      proposal: uncheckedProposal,
      receiverWallet: receiverWallet,
    );
    final (proposalReq, proposalCtx) = await payjoinProposal.extractV2Req();
    final res = await http.post(
      Uri.parse(proposalReq.url.asString()),
      body: proposalReq.body,
      headers: {
        'Content-Type': v2ContentType,
      },
    );
    await payjoinProposal.processRes(
      res: res.bodyBytes,
      ohttpContext: proposalCtx,
    );

    return (originalTx, payjoinProposal);
  }

  Future<String> getTxIdFromPsbt(
    String psbtBase64,
  ) async {
    final psbt = await bdk.PartiallySignedTransaction.fromString(psbtBase64);
    final txId = psbt.extractTx().txid();
    return txId;
  }

  Future<String> processV1Proposal(
    send.RequestContext reqCtx,
    String proposalPsbt,
  ) async {
    final (_, ctx) = await reqCtx.extractV1();
    final checkedProposal =
        await ctx.processResponse(response: utf8.encode(proposalPsbt));
    debugPrint('Processed Response: $checkedProposal');
    return checkedProposal;
  }

  Future<String> processV2Proposal(
    send.RequestContext reqCtx,
    String proposalPsbt,
  ) async {
    final (_, ctx) = await reqCtx.extractV2(
      ohttpProxyUrl: await pj_uri.Url.fromStr(payjoinDirectory),
    );
    final checkedProposal =
        await ctx.processResponse(response: utf8.encode(proposalPsbt));
    debugPrint('Processed Response: $checkedProposal');
    return checkedProposal!; // Since this is called after the original request, the response should not be null
  }

  Future<bdk.Transaction> extractPjTx(
      bdk.Wallet senderWallet, String psbtString) async {
    final psbt = await bdk.PartiallySignedTransaction.fromString(psbtString);
    debugPrint('PSBT before: ${psbt.toString()}');
    senderWallet.sign(
        psbt: psbt,
        signOptions: const bdk.SignOptions(
            trustWitnessUtxo: true,
            allowAllSighashes: false,
            removePartialSigs: true,
            tryFinalize: true,
            signWithTapInternalKey: true,
            allowGrinding: false));
    debugPrint('PSBT after: ${psbt.toString()}');
    var transaction = psbt.extractTx();
    return transaction;
  }

  Future<v2.ActiveSession> _startV2ReceiveSession({
    required String address,
    required Network network,
    required int expireAfter,
  }) async {
    final ohttpRelayUrl = await pj_uri.Url.fromStr(ohttpRelay);
    final payjoinDirectoryUrl = await pj_uri.Url.fromStr(payjoinDirectory);
    pj_uri.OhttpKeys ohttpKeys = await pj_uri.fetchOhttpKeys(
      ohttpRelay: ohttpRelayUrl,
      payjoinDirectory: payjoinDirectoryUrl,
    );

    final session = await v2.SessionInitializer.create(
      address: address,
      ohttpRelay: ohttpRelayUrl,
      directory: payjoinDirectoryUrl,
      ohttpKeys: ohttpKeys,
      network: Network.signet,
      expireAfter: BigInt.from(expireAfter),
    );

    final (req, ctx) = await session.extractReq();
    final response = await http.post(
      Uri.parse(req.url.asString()),
      body: req.body,
      headers: {
        'Content-Type': v2ContentType,
      },
    );
    final activeSession = await session.processRes(
      body: response.bodyBytes,
      ctx: ctx,
    );

    return activeSession;
  }

  Future<v1.PayjoinProposal> _handleV1Proposal({
    required v1.UncheckedProposal proposal,
    required bdk.Wallet receiverWallet,
  }) async {
    try {
      final _ = await proposal.extractTxToScheduleBroadcast();
      final ownedInputs =
          await proposal.checkBroadcastSuitability(canBroadcast: (e) async {
        return true;
      });
      final mixedInputScripts = await ownedInputs.checkInputsNotOwned(
          isOwned: (i) => _isOwned(i, receiverWallet));
      final seenInputs = await mixedInputScripts.checkNoMixedInputScripts();
      final payjoin =
          await (await seenInputs.checkNoInputsSeenBefore(isKnown: (e) async {
        return false;
      }))
              .identifyReceiverOutputs(
        isReceiverOutput: (i) => _isOwned(i, receiverWallet),
      );

      final availableInputs = receiverWallet.listUnspent();
      Map<BigInt, types.OutPoint> candidateInputs = {
        for (var input in availableInputs)
          input.txout.value: types.OutPoint(
            txid: input.outpoint.txid.toString(),
            vout: input.outpoint.vout,
          )
      };
      final selectedOutpoint = await payjoin.tryPreservingPrivacy(
        candidateInputs: candidateInputs,
      );
      var selectedUtxo = availableInputs.firstWhere(
          (i) =>
              i.outpoint.txid == selectedOutpoint.txid &&
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
      await payjoin.contributeWitnessInput(
        txo: txoToContribute,
        outpoint: outpointToContribute,
      );

      await payjoin.trySubstituteReceiverOutput(
          generateScript: () async => receiverWallet
              .getAddress(addressIndex: const bdk.AddressIndex.increase())
              .address
              .scriptPubkey()
              .bytes);
      final payjoinProposal = await payjoin.finalizeProposal(
        processPsbt: (i) => _processPsbt(i, receiverWallet),
      );
      return payjoinProposal;
    } on Exception catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<(bdk.Transaction originalTx, v2.PayjoinProposal)> _handleV2Request({
    required v2.UncheckedProposal proposal,
    required bdk.Wallet receiverWallet,
  }) async {
    try {
      final originalTxBytes = await proposal.extractTxToScheduleBroadcast();
      final originalTx =
          await bdk.Transaction.fromBytes(transactionBytes: originalTxBytes);

      final ownedInputs =
          await proposal.checkBroadcastSuitability(canBroadcast: (e) async {
        return true;
      });
      final mixedInputScripts = await ownedInputs.checkInputsNotOwned(
          isOwned: (i) => _isOwned(i, receiverWallet));
      final seenInputs = await mixedInputScripts.checkNoMixedInputScripts();
      final payjoin =
          await (await seenInputs.checkNoInputsSeenBefore(isKnown: (e) async {
        return false;
      }))
              .identifyReceiverOutputs(
        isReceiverOutput: (i) => _isOwned(i, receiverWallet),
      );

      final availableInputs = receiverWallet.listUnspent();
      Map<BigInt, types.OutPoint> candidateInputs = {
        for (var input in availableInputs)
          input.txout.value: types.OutPoint(
            txid: input.outpoint.txid.toString(),
            vout: input.outpoint.vout,
          )
      };
      final selectedOutpoint = await payjoin.tryPreservingPrivacy(
        candidateInputs: candidateInputs,
      );
      var selectedUtxo = availableInputs.firstWhere(
          (i) =>
              i.outpoint.txid == selectedOutpoint.txid &&
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
      await payjoin.contributeWitnessInput(
        txo: txoToContribute,
        outpoint: outpointToContribute,
      );

      /* PjUri is generated with pjos=0, so no output substitution is permitted
      await payjoin.trySubstituteReceiverOutput(
          generateScript: () async => receiverWallet
              .getAddress(addressIndex: const bdk.AddressIndex.increase())
              .address
              .scriptPubkey()
              .bytes);*/
      final payjoinProposal = await payjoin.finalizeProposal(
          processPsbt: (i) => _processPsbt(i, receiverWallet));
      return (originalTx, payjoinProposal);
    } on Exception catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<bool> _isOwned(Uint8List bytes, bdk.Wallet wallet) async {
    final script = bdk.ScriptBuf(bytes: bytes);
    return wallet.isMine(script: script);
  }

  Future<String> _processPsbt(String preProcessed, bdk.Wallet wallet) async {
    final psbt = await bdk.PartiallySignedTransaction.fromString(preProcessed);
    debugPrint('PSBT before: ${psbt.toString()}');
    await wallet.sign(
      psbt: psbt,
      signOptions: const bdk.SignOptions(
        trustWitnessUtxo: true,
        allowAllSighashes: false,
        removePartialSigs: true,
        tryFinalize: true,
        signWithTapInternalKey: true,
        allowGrinding: false,
      ),
    );
    debugPrint('PSBT after: ${psbt.toString()}');
    return psbt.asString();
  }
}
