class SourceParams {
  final String? cancelToken;

  final Map<String, dynamic>? customParams;

  const SourceParams({
    this.cancelToken,
    this.customParams,
  });

  Map<String, dynamic> toJson() => {
        if (cancelToken != null) 'token': cancelToken,
        if (customParams != null) ...customParams!,
      };

  @override
  String toString() => 'SourceParams(token: $cancelToken, custom: $customParams)';
}
