import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/di/injection.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/get_current_user_usecase.dart';

// ========== Use Case Providers ==========

final loginUseCaseProvider = Provider<LoginUseCase>(
  (ref) => getIt<LoginUseCase>(),
);

final registerUseCaseProvider = Provider<RegisterUseCase>(
  (ref) => getIt<RegisterUseCase>(),
);

final logoutUseCaseProvider = Provider<LogoutUseCase>(
  (ref) => getIt<LogoutUseCase>(),
);

final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>(
  (ref) => getIt<GetCurrentUserUseCase>(),
);

// ========== State Providers ==========

/// Current user provider
final currentUserProvider = FutureProvider<User?>((ref) async {
  final useCase = ref.watch(getCurrentUserUseCaseProvider);
  final result = await useCase();

  return result.fold(
    (failure) {
      debugPrint('Error getting current user: ${failure.message}');
      return null;
    },
    (user) => user,
  );
});

/// Current user ID provider (derived from currentUserProvider)
final currentUserIdProvider = Provider<String?>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) => user?.id,
    loading: () => null,
    error: (_, __) => null,
  );
});

// ========== Auth State Notifiers ==========

/// Login state notifier
final loginProvider = StateNotifierProvider<LoginNotifier, AsyncValue<User>>(
  (ref) => LoginNotifier(ref.watch(loginUseCaseProvider)),
);

class LoginNotifier extends StateNotifier<AsyncValue<User>> {
  final LoginUseCase _loginUseCase;

  LoginNotifier(this._loginUseCase) : super(const AsyncValue.loading());

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();

    final result = await _loginUseCase(email: email, password: password);

    state = result.fold(
      (failure) => AsyncValue.error(failure.message, StackTrace.current),
      (user) => AsyncValue.data(user),
    );
  }

  void reset() {
    state = const AsyncValue.loading();
  }
}

/// Register state notifier
final registerProvider =
    StateNotifierProvider<RegisterNotifier, AsyncValue<User>>(
  (ref) => RegisterNotifier(ref.watch(registerUseCaseProvider)),
);

class RegisterNotifier extends StateNotifier<AsyncValue<User>> {
  final RegisterUseCase _registerUseCase;

  RegisterNotifier(this._registerUseCase) : super(const AsyncValue.loading());

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = const AsyncValue.loading();

    final result = await _registerUseCase(
      email: email,
      password: password,
      fullName: fullName,
    );

    state = result.fold(
      (failure) => AsyncValue.error(failure.message, StackTrace.current),
      (user) => AsyncValue.data(user),
    );
  }

  void reset() {
    state = const AsyncValue.loading();
  }
}

/// Logout state notifier
final logoutProvider = StateNotifierProvider<LogoutNotifier, AsyncValue<void>>(
  (ref) => LogoutNotifier(ref.watch(logoutUseCaseProvider)),
);

class LogoutNotifier extends StateNotifier<AsyncValue<void>> {
  final LogoutUseCase _logoutUseCase;

  LogoutNotifier(this._logoutUseCase) : super(const AsyncValue.data(null));

  Future<void> logout() async {
    state = const AsyncValue.loading();

    final result = await _logoutUseCase();

    state = result.fold(
      (failure) => AsyncValue.error(failure.message, StackTrace.current),
      (_) => const AsyncValue.data(null),
    );
  }
}

/// Auth state provider - combines login/register/logout states
final authStateProvider = Provider<AuthState>((ref) {
  final userAsync = ref.watch(currentUserProvider);

  return userAsync.when(
    data: (user) => user != null
        ? AuthState.authenticated(user)
        : AuthState.unauthenticated(),
    loading: () => AuthState.loading(),
    error: (error, _) => AuthState.error(error.toString()),
  );
});

/// Auth state class
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user;
  final String? error;

  const AuthState({
    required this.isAuthenticated,
    required this.isLoading,
    this.user,
    this.error,
  });

  factory AuthState.authenticated(User user) {
    return AuthState(
      isAuthenticated: true,
      isLoading: false,
      user: user,
    );
  }

  factory AuthState.unauthenticated() {
    return const AuthState(
      isAuthenticated: false,
      isLoading: false,
    );
  }

  factory AuthState.loading() {
    return const AuthState(
      isAuthenticated: false,
      isLoading: true,
    );
  }

  factory AuthState.error(String message) {
    return AuthState(
      isAuthenticated: false,
      isLoading: false,
      error: message,
    );
  }
}
