// PLANTILLAS DE ASIENTOS FRECUENTES ("¿Qué ha pasado?"), como los asientos predefinidos de ContaPlus / A3
// o los diarios periódicos de Business Central. Cada línea dice de qué cuenta del PGC cuelga (prefix) y en qué
// lado va (side). Al elegir una, se rellenan las SUBCUENTAS de la empresa (la primera que exista de ese grupo) y
// el usuario solo escribe los importes; en la línea marcada como total, el botón "=" cuadra el asiento.
// No calculan el IVA/IGIC: para eso está "Registrar factura", que lo hace con los tipos configurados.
import { ArrowDownToLine, ArrowUpFromLine, Banknote, ShoppingCart, Users } from 'lucide-react'

export const TEMPLATES = [
  { id: 'purchase', icon: ShoppingCart, lines: [
    { prefix: '600', side: 'debit' },                    // Compras de mercaderías
    { prefix: '472', side: 'debit' },                    // IVA / IGIC soportado
    { prefix: '400', side: 'credit', total: true },      // Proveedores
  ] },
  { id: 'sale', icon: Banknote, lines: [
    { prefix: '430', side: 'debit', total: true },       // Clientes
    { prefix: '700', side: 'credit' },                   // Ventas de mercaderías
    { prefix: '477', side: 'credit' },                   // IVA / IGIC repercutido
  ] },
  { id: 'collect', icon: ArrowDownToLine, lines: [
    { prefix: '572', side: 'debit' },                    // Bancos
    { prefix: '430', side: 'credit', total: true },      // Clientes
  ] },
  { id: 'pay', icon: ArrowUpFromLine, lines: [
    { prefix: '400', side: 'debit' },                    // Proveedores
    { prefix: '572', side: 'credit', total: true },      // Bancos
  ] },
  { id: 'payroll', icon: Users, lines: [
    { prefix: '640', side: 'debit' },                    // Sueldos y salarios (bruto)
    { prefix: '642', side: 'debit' },                    // Seguridad Social a cargo de la empresa
    { prefix: '476', side: 'credit' },                   // Organismos de la Seguridad Social, acreedores
    { prefix: '4751', side: 'credit' },                  // HP acreedora por retenciones practicadas (IRPF)
    { prefix: '572', side: 'credit', total: true },      // Bancos: el neto que se paga
  ] },
]
