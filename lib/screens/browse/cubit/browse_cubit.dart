import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:yt_music/ytmusic.dart';

part 'browse_state.dart';

class BrowseCubit extends Cubit<BrowseState> {
  final YTMusic _ytMusic;
  final Map<String, dynamic> endpoint;
  BrowseCubit(this._ytMusic, {required this.endpoint}) : super(BrowseLoading());
  Future<void> fetch() async {
    emit(const BrowseLoading());
    try {
      final feed = await _ytMusic.browse(body: endpoint, limit: 2);
      emit(BrowseSuccess(
        header: feed['header'] ?? {},
        sections: feed['sections'],
        continuation: feed['continuation'],
        loadingMore: false,
      ));
    } catch (e, st) {
      emit(BrowseError(e.toString(), st.toString()));
    }
  }

  Future<void> fetchNext() async {
    final current = state;
    if (current is! BrowseSuccess) return;
    if (current.loadingMore || current.continuation == null) return;
    
    emit(current.copyWith(loadingMore: true));
    try {
      final feed = await _ytMusic.browseContinuation(
          additionalParams: current.continuation!);
      emit(
        BrowseSuccess(
          header: current.header,
          sections: [...current.sections, ...feed['sections']],
          continuation: feed['continuation'],
          loadingMore: false, 
        ),
      );
    } catch (e, st) {
      emit(BrowseError(e.toString(), st.toString()));
    }
  }
}
