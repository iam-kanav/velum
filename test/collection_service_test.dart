import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velum/features/library/data/services/collection_service.dart';

void main() {
  late CollectionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = CollectionService(await SharedPreferences.getInstance());
  });

  test('create, rename and delete keep order and survive reloads', () async {
    final a = await service.create('Classics', ['/a.epub', '/b.epub']);
    await service.create('To read', []);
    await service.rename(a.id, 'Old classics');

    expect(service.load().map((c) => c.name), ['Old classics', 'To read']);
    expect(service.load().first.bookPaths, ['/a.epub', '/b.epub']);

    await service.delete(a.id);
    expect(service.load().map((c) => c.name), ['To read']);
  });

  test('adding books never duplicates; removing drops only those', () async {
    final c = await service.create('Classics', ['/a.epub']);
    await service.setMembership(c.id, ['/a.epub', '/b.epub'], true);
    expect(service.load().single.bookPaths, ['/a.epub', '/b.epub']);

    await service.setMembership(c.id, ['/a.epub'], false);
    expect(service.load().single.bookPaths, ['/b.epub']);
  });

  test('a book removed from the library leaves every collection', () async {
    await service.create('One', ['/a.epub', '/b.epub']);
    await service.create('Two', ['/a.epub']);
    await service.forgetBook('/a.epub');
    expect(service.load().map((c) => c.bookPaths), [
      ['/b.epub'],
      <String>[],
    ]);
  });
}
