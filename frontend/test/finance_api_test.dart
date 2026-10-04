import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/finance_api.dart';
import 'package:frontend/data/finance_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('OTP endpoints send phone details and return a bearer token', () async {
    final requests = <http.Request>[];
    final api = HttpFinanceApi(
      baseUrl: 'https://finance.test',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/otp/start') {
          return http.Response('{"status":"pending"}', 202);
        }
        return http.Response('{"access_token":"signed-token"}', 200);
      }),
    );

    await api.startPhoneVerification('+14155550123');
    final token = await api.verifyPhone('+14155550123', '123456');

    expect(token, 'signed-token');
    expect(jsonDecode(requests.first.body), {'phone_number': '+14155550123'});
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(requests.last.body), {
      'phone_number': '+14155550123',
      'code': '123456',
    });
  });

  test('transaction reads include bearer auth and serialize filter query', () async {
    late http.Request captured;
    final api = HttpFinanceApi(
      baseUrl: 'https://finance.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              'id': 7,
              'description': 'Coffee',
              'category': 'Food',
              'amount_minor': 450,
              'currency': 'USD',
              'occurred_at': '2026-10-01T12:00:00Z',
              'transaction_type': 'expense',
              'created_at': '2026-10-01T12:00:00Z',
            },
          ]),
          200,
        );
      }),
    )..setAccessToken('signed-token');

    final result = await api.getTransactions(
      const TransactionFilters(
        search: 'coffee',
        transactionType: 'expense',
        currency: 'USD',
      ),
    );

    expect(captured.headers['Authorization'], 'Bearer signed-token');
    expect(captured.url.queryParameters['search'], 'coffee');
    expect(captured.url.queryParameters['transaction_type'], 'expense');
    expect(result.single.amountMinor, 450);
  });

  test('server errors produce safe API errors with status codes', () async {
    final api = HttpFinanceApi(
      baseUrl: 'https://finance.test',
      client: MockClient(
        (_) async => http.Response('{"detail":"Code expired"}', 400),
      ),
    );

    await expectLater(
      api.startPhoneVerification('+14155550123'),
      throwsA(
        isA<FinanceApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.message, 'message', 'Code expired'),
      ),
    );
  });

  test('network failures are identified for offline handling', () async {
    final api = HttpFinanceApi(
      baseUrl: 'https://finance.test',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    await expectLater(
      api.startPhoneVerification('+14155550123'),
      throwsA(
        isA<FinanceApiException>()
            .having((error) => error.isNetworkError, 'isNetworkError', isTrue),
      ),
    );
  });

  test('CSV export uses authenticated filtered endpoint', () async {
    late http.Request captured;
    final api = HttpFinanceApi(
      baseUrl: 'https://finance.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response('description,amount_minor\nCoffee,450', 200);
      }),
    )..setAccessToken('signed-token');

    final csv = await api.exportTransactions(
      const TransactionFilters(search: 'Coffee', currency: 'USD'),
    );

    expect(csv, contains('Coffee,450'));
    expect(captured.url.path, '/transactions/export.csv');
    expect(captured.url.queryParameters['search'], 'Coffee');
    expect(captured.url.queryParameters.containsKey('limit'), isFalse);
    expect(captured.headers['Authorization'], 'Bearer signed-token');
  });
}
