// UI texts in English. Keys must match es.js exactly.
export default {
  appTitle: 'Mini ERP · Accounting',
  language: 'Language',

  // Sign in
  login: 'Sign in',
  email: 'Email',
  password: 'Password (min. 6)',
  signIn: 'Sign in',
  signUp: 'Sign up',
  signOut: 'Sign out',
  userCreated: 'User created. If you are not signed in automatically, press Sign in.',

  // Companies
  myCompanies: 'My companies',
  noCompanies: "You don't have any companies yet.",
  newCompany: 'New company',
  companyName: 'Name',
  vatNo: 'VAT registration no.',
  createCompany: 'Create company',

    // Company screen
  back: 'Companies',
  tabEntry: 'New entry',
  tabJournal: 'General journal',
  tabAccounts: 'Accounts',

  // Chart of accounts
  chartOfAccounts: 'Chart of accounts',
  searchAccount: 'Search by number or name…',
  newAccount: 'New posting account',
  newAccountHelp: 'A {n}-digit posting account starting with its PGC account. E.g. 57200001 Bank, 43000001 Customer.',
  accountNo: 'Number',
  accountNameEs: 'Name (Spanish)',
  accountNameEn: 'English name (optional)',
  createAccount: 'Create account',

  // Journal entries
  newEntry: 'New journal entry',
  postingDate: 'Posting date',
  documentNo: 'Document no.',
  entryDescription: 'Entry description',
  selectAccount: 'Select account…',
  noPostingAccounts: 'First create posting accounts in the Accounts tab.',
  debit: 'Debit',
  credit: 'Credit',
  addLine: 'Add line',
  removeLine: 'Remove line',
  fillDifference: 'Put the difference here',
  balanced: 'Balanced',
  difference: 'Difference',
  saveDraft: 'Save draft',
  post: 'Post',
  postedAs: 'Entry posted as no. {n}.',
  savedDraft: 'Draft saved.',
  noFiscalYear: 'There is no open fiscal year for that date.',
  needTwoLines: 'An entry needs at least 2 lines with account and amount.',
  needDescription: 'Write the entry description.',
  unbalanced: 'The entry is unbalanced: debit must equal credit.',

  // General journal
  generalJournal: 'General journal',
  noEntries: 'There are no posted entries yet.',
  entry: 'Entry',
  account: 'Account',


    // Demo and limits
  demoCompanies: 'Demo companies',
  demoHelp: 'Sample companies to explore: general journal, accounts and reports. Read only.',
  demoBadge: 'DEMO',
  readOnly: 'Read only · demo company',
  publishDemo: 'Publish as demo',
  unpublishDemo: 'Stop publishing as demo',
  companyLimit: 'You have reached your account limit of {n} company(ies).',
  
    // CSV import
  importAccounts: 'Import posting accounts (CSV)',
  importHelp: 'Prepare a CSV in Excel with the columns subcuenta, nombre_es and nombre_en (optional). {n}-digit accounts. You will see a preview first: nothing is saved until you press Import.',
  chooseCsv: 'Choose CSV file',
  downloadTemplate: 'Download template',
  validating: 'Validating with the database…',
  importNew: 'New',
  importUpdate: 'Updated',
  importErrors: 'Errors',
  status: 'Status',
  importStatus: { insert: 'New', update: 'Update', error: 'Error' },
  importNow: 'Import {n} accounts',
  importDone: 'Import completed: {n} rows.',
  fixErrors: 'Fix the errors in the file and load it again. It is all or nothing.',
  csvMissingColumns: 'Column "subcuenta" not found. Download the template to see the format.',
  cancel: 'Cancel',

  industry: {
    services: 'Services',
    retail: 'Retail',
    manufacturing: 'Manufacturing',
    ecommerce: 'E-commerce',
  },
  territory: {
    canary_islands: 'Canary Islands (IGIC)',
    mainland: 'Mainland Spain (VAT)',
  },
}