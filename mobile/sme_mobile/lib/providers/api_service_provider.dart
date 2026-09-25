import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';

final apiServiceProvider = Provider<Dio>((ref) => ApiService.dio);
