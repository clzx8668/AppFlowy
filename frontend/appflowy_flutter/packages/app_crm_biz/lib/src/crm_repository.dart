import 'package:app_biz_store/app_biz_store.dart';
import 'package:nanoid/nanoid.dart';

import 'crm_customer.dart';

/// CRM 表结构（写在独立业务库里）。
const String kCrmCustomerTable = 'crm_customers';

const List<BusinessMigration> kCrmMigrations = [
  BusinessMigration('crm', 1, [
    '''
    CREATE TABLE IF NOT EXISTS $kCrmCustomerTable (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      company TEXT NOT NULL DEFAULT '',
      stage TEXT NOT NULL DEFAULT '',
      owner TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_crm_customers_updated_at '
        'ON $kCrmCustomerTable (updated_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_crm_customers_stage '
        'ON $kCrmCustomerTable (stage);',
  ]),
];

/// CRM 仓储契约。
abstract interface class CrmRepository {
  Future<List<CrmCustomer>> listCustomers({String? stage});

  Future<CrmCustomer> createCustomer({
    required String name,
    String company,
    String stage,
    String phone,
  });

  Future<void> updateCustomer(CrmCustomer customer);

  Future<void> deleteCustomer(String id);
}

/// 基于业务库（独立 Sqlite）的 CRM 仓储实现。
class CrmRepositoryImpl implements CrmRepository {
  CrmRepositoryImpl(this._db);

  final BusinessDatabase _db;

  @override
  Future<List<CrmCustomer>> listCustomers({String? stage}) async {
    final rows = stage == null || stage.isEmpty
        ? _db.raw.select(
            'SELECT * FROM $kCrmCustomerTable ORDER BY updated_at DESC;',
          )
        : _db.raw.select(
            'SELECT * FROM $kCrmCustomerTable WHERE stage = ? '
            'ORDER BY updated_at DESC;',
            [stage],
          );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<CrmCustomer> createCustomer({
    required String name,
    String company = '',
    String stage = '线索',
    String phone = '',
  }) async {
    final now = DateTime.now();
    final customer = CrmCustomer(
      id: nanoid(12),
      name: name,
      company: company,
      stage: stage,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
    await updateCustomer(customer);
    return customer;
  }

  @override
  Future<void> updateCustomer(CrmCustomer customer) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmCustomerTable '
      '(id, name, company, stage, owner, phone, note, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        customer.id,
        customer.name,
        customer.company,
        customer.stage,
        customer.owner,
        customer.phone,
        customer.note,
        customer.createdAt.millisecondsSinceEpoch,
        customer.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> deleteCustomer(String id) async {
    _db.raw.execute('DELETE FROM $kCrmCustomerTable WHERE id = ?;', [id]);
  }

  CrmCustomer _fromRow(Row row) {
    return CrmCustomer(
      id: row['id'] as String,
      name: row['name'] as String,
      company: row['company'] as String? ?? '',
      stage: row['stage'] as String? ?? '',
      owner: row['owner'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      note: row['note'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
