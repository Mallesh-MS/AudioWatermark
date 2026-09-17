List<double> embed(List<double> hostSamples, List<double> watermarkTones, double amplitude) {
  final mixed = List<double>.from(hostSamples);
  for (int index = 0; index < watermarkTones.length; index++) {
    final targetIndex = index;
    if (targetIndex >= mixed.length) {
      break;
    }
    mixed[targetIndex] = (mixed[targetIndex] + (amplitude * watermarkTones[index])).clamp(-1.0, 1.0);
  }
  return mixed;
}

List<double> extractRegion(List<double> mixedSamples, int startIndex, int length) {
  if (startIndex < 0 || startIndex + length > mixedSamples.length) {
    throw RangeError('Requested region exceeds sample bounds');
  }
  return mixedSamples.sublist(startIndex, startIndex + length);
}
