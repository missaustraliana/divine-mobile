// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dm_reactions_dao.dart';

// ignore_for_file: type=lint
mixin _$DmReactionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $DmMessageReactionsTable get dmMessageReactions =>
      attachedDatabase.dmMessageReactions;
  DmReactionsDaoManager get managers => DmReactionsDaoManager(this);
}

class DmReactionsDaoManager {
  final _$DmReactionsDaoMixin _db;
  DmReactionsDaoManager(this._db);
  $$DmMessageReactionsTableTableManager get dmMessageReactions =>
      $$DmMessageReactionsTableTableManager(
        _db.attachedDatabase,
        _db.dmMessageReactions,
      );
}
