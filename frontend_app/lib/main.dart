import 'package:flutter/widgets.dart';
import 'data/auth/auth_services.dart';
import 'data/auth/auth_storage.dart';
import 'data/api/client.dart';
import 'data/service/user_services.dart';

Future<void> main() async {
  print("Starting app...");
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient(
    baseUrl: 'http://10.0.2.2:8000',
    authStorage: AuthStorage(),
  );
  final authStorage = AuthStorage();
  final userServices = UserServices(apiClient: apiClient);
  final authServices = AuthServices(
    apiClient: apiClient,
    authStorage: authStorage,
    userServices: userServices,
  );

  final user = await authServices.tryGetCurrentUser();
  if (user == null) {
    print("No authenticated user.");
  } else {
    print("Current user: ${user.username}");
  }

  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
