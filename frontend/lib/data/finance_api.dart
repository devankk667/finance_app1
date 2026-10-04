import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:frontend/data/finance_models.dart';
import 'package:http/http.dart' as http;

abstract interface class FinanceApi {
  void setAccessToken(String? token);
  Future<void> startPhoneVerification(String phoneNumber);
  Future<String> verifyPhone(String phoneNumber, String code);
  Future<List<FinanceTransaction>> getTransactions(TransactionFilters filters);
  Future<FinanceSummary> getSummary(String currency);
  Future<FinanceTransaction> createTransaction(FinanceTransactionDraft draft);
  Future<FinanceTransaction> updateTransaction(
    int id,
    FinanceTransactionDraft draft,
  );
  Future<void> deleteTransaction(int id);
  Future<List<RecurringTemplate>> getRecurringTemplates();
  Future<RecurringTemplate> createRecurringTemplate(
    RecurringTemplateDraft draft,
  );
  Future<void> deleteRecurringTemplate(int id);
  Future<void> materializeDueRecurringTransactions();
  Future<String> exportTransactions(TransactionFilters filters);
}

class FinanceApiException implements Exception {
  const FinanceApiException(
    this.message, {
    this.statusCode,
    this.isNetworkError = false,
  });

  final String message;
  final int? statusCode;
  final bool isNetworkError;

  @override
  String toString() => message;
}

class HttpFinanceApi implements FinanceApi {
  HttpFinanceApi({
    String? baseUrl,
    http.Client? client,
  })  : _baseUrl = (baseUrl ?? _configuredBaseUrl).replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  static const _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final String _baseUrl;
  final http.Client _client;
  String? _accessToken;

  @override
  void setAccessToken(String? token) => _accessToken = token;

  @override
  Future<void> startPhoneVerification(String phoneNumber) async {
    await _request(
      'POST',
      '/auth/otp/start',
      body: {'phone_number': phoneNumber},
      authenticated: false,
    );
  }

  @override
  Future<String> verifyPhone(String phoneNumber, String code) async {
    final response = await _request(
      'POST',
      '/auth/otp/verify',
      body: {'phone_number': phoneNumber, 'code': code},
      authenticated: false,
    ) as Map<String, dynamic>;
    return response['access_token'] as String;
  }

  @override
  Future<List<FinanceTransaction>> getTransactions(
    TransactionFilters filters,
  ) async {
    final response = await _request(
      'GET',
      '/transactions',
      query: filters.toQueryParameters(),
    ) as List<dynamic>;
    return response
        .map(
          (entry) => FinanceTransaction.fromApi(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList();
  }

  @override
  Future<FinanceSummary> getSummary(String currency) async {
    final response = await _request(
      'GET',
      '/transactions/summary',
      query: {'currency': currency},
    ) as Map<String, dynamic>;
    return FinanceSummary.fromJson(response);
  }

  @override
  Future<FinanceTransaction> createTransaction(
    FinanceTransactionDraft draft,
  ) async {
    final response = await _request(
      'POST',
      '/transactions',
      body: draft.toApiJson(),
    ) as Map<String, dynamic>;
    return FinanceTransaction.fromApi(response);
  }

  @override
  Future<FinanceTransaction> updateTransaction(
    int id,
    FinanceTransactionDraft draft,
  ) async {
    final response = await _request(
      'PATCH',
      '/transactions/$id',
      body: draft.toApiJson(),
    ) as Map<String, dynamic>;
    return FinanceTransaction.fromApi(response);
  }

  @override
  Future<void> deleteTransaction(int id) async {
    await _request('DELETE', '/transactions/$id');
  }

  @override
  Future<List<RecurringTemplate>> getRecurringTemplates() async {
    final response = await _request('GET', '/recurring-templates') as List<dynamic>;
    return response
        .map(
          (entry) => RecurringTemplate.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList();
  }

  @override
  Future<RecurringTemplate> createRecurringTemplate(
    RecurringTemplateDraft draft,
  ) async {
    final response = await _request(
      'POST',
      '/recurring-templates',
      body: draft.toJson(),
    ) as Map<String, dynamic>;
    return RecurringTemplate.fromJson(response);
  }

  @override
  Future<void> deleteRecurringTemplate(int id) async {
    await _request('DELETE', '/recurring-templates/$id');
  }

  @override
  Future<void> materializeDueRecurringTransactions() async {
    await _request('POST', '/recurring-templates/materialize-due');
  }

  @override
  Future<String> exportTransactions(TransactionFilters filters) async {
    final response = await _request(
      'GET',
      '/transactions/export.csv',
      query: Map.of(filters.toQueryParameters())..remove('limit')..remove('offset'),
      expectJson: false,
    );
    return response as String;
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
    bool expectJson = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': expectJson ? 'application/json' : 'text/csv',
      if (body != null) 'Content-Type': 'application/json',
      if (authenticated && _accessToken != null)
        'Authorization': 'Bearer $_accessToken',
    };
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed = await _client.send(request).timeout(
        const Duration(seconds: 15),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var message = 'Request failed (${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
            message = decoded['detail'].toString();
          }
        } on FormatException {
          if (response.body.isNotEmpty) message = response.body;
        }
        throw FinanceApiException(message, statusCode: response.statusCode);
      }
      if (!expectJson || response.body.isEmpty) return response.body;
      return jsonDecode(response.body);
    } on FinanceApiException {
      rethrow;
    } on TimeoutException {
      throw const FinanceApiException(
        'The server did not respond in time. Check your connection and try again.',
        isNetworkError: true,
      );
    } on http.ClientException catch (error) {
      throw FinanceApiException(
        'Could not reach the finance server: ${error.message}',
        isNetworkError: true,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) debugPrint('Finance API error: $error\n$stackTrace');
      rethrow;
    }
  }
}
