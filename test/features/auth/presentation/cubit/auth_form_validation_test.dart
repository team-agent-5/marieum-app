import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';

void main() {
  group('AuthFormValidation.serverFields', () {
    test('shows Korean wording instead of server issue codes', () {
      final fields = AuthFormValidation.serverFields(
        const ValidationFailure(
          fieldErrors: {
            'password_confirm': ['Value error, password_confirm_mismatch'],
            'unknown_field': ['whatever'],
          },
        ),
      );
      expect(fields, {'password_confirm': '비밀번호가 일치하지 않아요'});
    });

    test('marks a taken ID on the ID field', () {
      expect(
        AuthFormValidation.serverFields(const ConflictFailure()),
        {'user_id': '이미 사용 중인 아이디예요'},
      );
    });
  });
}
