import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/period_utils.dart';
import 'budget_providers.dart';

@immutable
class HomeUiState {
  const HomeUiState({required this.showCloseBanner});

  final bool showCloseBanner;

  HomeUiState copyWith({bool? showCloseBanner}) {
    return HomeUiState(
      showCloseBanner: showCloseBanner ?? this.showCloseBanner,
    );
  }
}

class HomeUiController extends StateNotifier<HomeUiState> {
  HomeUiController(this._ref)
      : _currentBannerPeriodId = _initialClosablePeriodId(_ref),
        super(
          HomeUiState(
            showCloseBanner: _initialClosablePeriodId(_ref) != null,
          ),
        ) {
    _closablePeriodSub = _ref.listen<PeriodRef?>(
      periodToCloseProvider,
      (previous, next) {
        final nextId = next?.id;
        if (nextId != _currentBannerPeriodId) {
          _currentBannerPeriodId = nextId;
          state = state.copyWith(showCloseBanner: nextId != null);
        } else if (nextId == null && state.showCloseBanner) {
          state = state.copyWith(showCloseBanner: false);
        }
      },
      fireImmediately: false,
    );
    _ref.onDispose(_closablePeriodSub.close);
  }

  final Ref _ref;
  late final ProviderSubscription<PeriodRef?> _closablePeriodSub;
  String? _currentBannerPeriodId;

  static String? _initialClosablePeriodId(Ref ref) {
    return ref.read(periodToCloseProvider)?.id;
  }

  void hideCloseBanner() {
    if (!state.showCloseBanner) {
      return;
    }
    state = state.copyWith(showCloseBanner: false);
  }

  void showCloseBannerFor(PeriodRef period) {
    final id = period.id;
    _currentBannerPeriodId = id;
    if (state.showCloseBanner) {
      return;
    }
    state = state.copyWith(showCloseBanner: true);
  }
}

final homeUiStateProvider =
    StateNotifierProvider<HomeUiController, HomeUiState>((ref) {
  return HomeUiController(ref);
});
