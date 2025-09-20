import 'package:flutter/material.dart';

class CategoryCreateStub extends StatelessWidget {
  const CategoryCreateStub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая категория')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Здесь появится форма добавления категории. Планируется выбор цвета, иконки и типа операции.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
