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
    await service.update(a.id, name: 'Old classics', hideFromLibrary: true);

    expect(service.load().map((c) => c.name), ['Old classics', 'To read']);
    expect(service.load().first.bookPaths, ['/a.epub', '/b.epub']);
    expect(service.load().first.hideFromLibrary, isTrue);
    expect(service.load().last.hideFromLibrary, isFalse);

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
    await service.forgetBooks(['/a.epub']);
    expect(service.load().map((c) => c.bookPaths), [
      ['/b.epub'],
      <String>[],
    ]);
  });

  test('a book whose file moved keeps its place in its collections', () async {
    await service.create('One', ['/a.epub', '/b.epub']);
    await service.create('Two', ['/c.epub']);
    await service.moveBooks({'/a.epub': '/new/a.epub'});
    expect(service.load().map((c) => c.bookPaths), [
      ['/new/a.epub', '/b.epub'],
      ['/c.epub'],
    ]);
  });

  test('a collection that cannot be read does not take the others', () async {
    SharedPreferences.setMockInitialValues({
      'book_collections':
          '[{"id":"1","name":"Kept","bookPaths":["/a.epub"]},'
          '{"id":"2"},"junk",'
          '{"id":"3","name":"Also kept"}]',
    });
    service = CollectionService(await SharedPreferences.getInstance());
    expect(service.load().map((c) => c.name), ['Kept', 'Also kept']);

    // A later change saves the readable ones, not an empty list.
    await service.setMembership('3', ['/b.epub'], true);
    expect(service.load().map((c) => c.bookPaths), [
      ['/a.epub'],
      ['/b.epub'],
    ]);
  });
}
