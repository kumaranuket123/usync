import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:usync/domain/repositories/i_auth_repository.dart';
import 'package:usync/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:usync/presentation/features/auth/screens/login_screen.dart';

class _FakeAuth implements IAuthRepository {
  @override
  Stream<void> get signedOut => const Stream.empty();
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  // Phone sizes and font scales that tend to overflow; a RenderFlex overflow
  // makes the test fail.
  for (final size in const [Size(320, 480), Size(360, 640), Size(411, 891)]) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets('login fits $size at ${scale}x text', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: BlocProvider(
            create: (_) => AuthBloc(authRepository: _FakeAuth()),
            child: const LoginScreen(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Unmount so the screen's animation timers finish before the test ends.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}
