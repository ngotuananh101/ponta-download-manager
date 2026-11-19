import 'package:material_ui/material_ui.dart';

class UpdateDot extends StatelessWidget {
  const UpdateDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(label: 'Updates available',
    child: Container(width: 6, height: 6,
      decoration: const BoxDecoration(color: Color(0xFFFFC107), shape: BoxShape.circle)));
}
