import '../Eval/dart/model/source_preference.dart';
import '../Models/Source.dart';
import 'lib.dart';

List<SourcePreference> getSourcePreference({required MSource source}) {
  return getCachedExtensionService(source).getSourcePreferences();
}
