/// Cloud voices offered in settings; [id] is the provider voice name.
enum CloudVoice {
  female('Aoede', '여성'),
  male('Puck', '남성');

  const CloudVoice(this.id, this.label);
  final String id;
  final String label;
}
