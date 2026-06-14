import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { ArrowUp, ArrowDown, Lock, Palette, Check, Plus, Trash2, Pencil, X } from 'lucide-react';
import { toast } from 'sonner';

export default function StatusManagement() {
  const [statuses, setStatuses] = useState<any[]>([]);
  const [orderCounts, setOrderCounts] = useState<Record<string, number>>({});
  const [editingColorId, setEditingColorId] = useState<string | null>(null);
  const [colorValue, setColorValue] = useState('');
  const [editingNameId, setEditingNameId] = useState<string | null>(null);
  const [nameValue, setNameValue] = useState('');
  const [newName, setNewName] = useState('');
  const [newColor, setNewColor] = useState('#6b7280');
  const [adding, setAdding] = useState(false);

  const addStatus = async () => {
    const name = newName.trim();
    if (!name) { toast.error('أدخل اسم الحالة'); return; }
    const maxOrder = statuses.reduce((m, s) => Math.max(m, s.sort_order || 0), 0);
    const { error } = await supabase.from('order_statuses').insert({ name, color: newColor, sort_order: maxOrder + 1 });
    if (error) { toast.error(error.message); return; }
    toast.success('تمت إضافة الحالة');
    setNewName(''); setNewColor('#6b7280'); setAdding(false);
    loadData();
  };

  const deleteStatus = async (s: any) => {
    if ((orderCounts[s.id] || 0) > 0) { toast.error('لا يمكن حذف حالة مستخدمة في أوردرات'); return; }
    if (!confirm(`حذف الحالة "${s.name}"؟`)) return;
    const { error } = await supabase.from('order_statuses').delete().eq('id', s.id);
    if (error) { toast.error(error.message); return; }
    toast.success('تم الحذف');
    loadData();
  };

  const saveName = async (id: string) => {
    const name = nameValue.trim();
    if (!name) return;
    const { error } = await supabase.from('order_statuses').update({ name }).eq('id', id);
    if (error) { toast.error(error.message); return; }
    toast.success('تم التحديث');
    setEditingNameId(null);
    loadData();
  };

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    const [statusRes, ordersRes] = await Promise.all([
      supabase.from('order_statuses').select('*').order('sort_order'),
      supabase.from('orders').select('status_id'),
    ]);
    setStatuses(statusRes.data || []);
    const counts: Record<string, number> = {};
    (ordersRes.data || []).forEach(o => { if (o.status_id) counts[o.status_id] = (counts[o.status_id] || 0) + 1; });
    setOrderCounts(counts);
  };

  const moveUp = async (index: number) => {
    if (index === 0) return;
    const current = statuses[index];
    const prev = statuses[index - 1];
    await Promise.all([
      supabase.from('order_statuses').update({ sort_order: prev.sort_order }).eq('id', current.id),
      supabase.from('order_statuses').update({ sort_order: current.sort_order }).eq('id', prev.id),
    ]);
    loadData();
  };

  const moveDown = async (index: number) => {
    if (index === statuses.length - 1) return;
    const current = statuses[index];
    const next = statuses[index + 1];
    await Promise.all([
      supabase.from('order_statuses').update({ sort_order: next.sort_order }).eq('id', current.id),
      supabase.from('order_statuses').update({ sort_order: current.sort_order }).eq('id', next.id),
    ]);
    loadData();
  };

  const startEditColor = (status: any) => {
    setEditingColorId(status.id);
    setColorValue(status.color || '#6b7280');
  };

  const saveColor = async (statusId: string) => {
    const { error } = await supabase.from('order_statuses').update({ color: colorValue }).eq('id', statusId);
    if (error) {
      toast.error('خطأ في حفظ اللون');
    } else {
      toast.success('تم تحديث اللون');
      setEditingColorId(null);
      loadData();
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <h1 className="text-xl sm:text-2xl font-bold">إدارة الحالات</h1>
        <Button onClick={() => setAdding(v => !v)} size="sm" className="gap-1">
          <Plus className="h-4 w-4" /> إضافة حالة جديدة
        </Button>
      </div>

      {adding && (
        <Card className="bg-card border-border">
          <CardContent className="p-3 flex flex-wrap gap-2 items-center">
            <Input
              placeholder="اسم الحالة (مثال: تم التسليم)"
              value={newName}
              onChange={e => setNewName(e.target.value)}
              className="flex-1 min-w-[200px] bg-secondary border-border"
              onKeyDown={e => { if (e.key === 'Enter') addStatus(); }}
            />
            <Input type="color" value={newColor} onChange={e => setNewColor(e.target.value)} className="w-14 h-9 p-0 border-0 cursor-pointer bg-transparent" />
            <Button size="sm" onClick={addStatus}><Check className="h-4 w-4 ml-1" /> حفظ</Button>
            <Button size="sm" variant="ghost" onClick={() => { setAdding(false); setNewName(''); }}><X className="h-4 w-4" /></Button>
          </CardContent>
        </Card>
      )}

      <Card className="bg-card border-border">
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow className="border-border">
                  <TableHead className="w-16 text-center">ترتيب</TableHead>
                  <TableHead className="text-right">الحالة</TableHead>
                  <TableHead className="text-center">اللون</TableHead>
                  <TableHead className="text-center">عدد الأوردرات</TableHead>
                  <TableHead className="text-center">إجراءات</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {statuses.map((s, i) => (
                  <TableRow key={s.id} className="border-border">
                    <TableCell>
                      <div className="flex gap-1 justify-center">
                        <Button size="icon" variant="ghost" className="h-6 w-6" onClick={() => moveUp(i)} disabled={i === 0}><ArrowUp className="h-3 w-3" /></Button>
                        <Button size="icon" variant="ghost" className="h-6 w-6" onClick={() => moveDown(i)} disabled={i === statuses.length - 1}><ArrowDown className="h-3 w-3" /></Button>
                      </div>
                    </TableCell>
                    <TableCell>
                      {editingNameId === s.id ? (
                        <div className="flex items-center gap-1">
                          <Input
                            value={nameValue}
                            onChange={e => setNameValue(e.target.value)}
                            onKeyDown={e => { if (e.key === 'Enter') saveName(s.id); if (e.key === 'Escape') setEditingNameId(null); }}
                            className="h-7 w-40 bg-secondary border-border"
                            autoFocus
                          />
                          <Button size="icon" variant="ghost" className="h-7 w-7 text-green-500" onClick={() => saveName(s.id)}>
                            <Check className="h-4 w-4" />
                          </Button>
                          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEditingNameId(null)}>
                            <X className="h-4 w-4" />
                          </Button>
                        </div>
                      ) : (
                        <Badge style={{ backgroundColor: (s.color || '#6b7280') + '30', color: s.color || '#6b7280' }}>{s.name}</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-center">
                      {editingColorId === s.id ? (
                        <div className="flex items-center gap-1 justify-center">
                          <Input
                            type="color"
                            value={colorValue}
                            onChange={(e) => setColorValue(e.target.value)}
                            className="w-10 h-8 p-0 border-0 cursor-pointer bg-transparent"
                          />
                          <Button size="icon" variant="ghost" className="h-7 w-7 text-green-500" onClick={() => saveColor(s.id)}>
                            <Check className="h-4 w-4" />
                          </Button>
                        </div>
                      ) : (
                        <div
                          className="w-6 h-6 rounded-full mx-auto cursor-pointer hover:ring-2 hover:ring-primary transition-all"
                          style={{ backgroundColor: s.color || '#6b7280' }}
                          onClick={() => startEditColor(s)}
                          title="اضغط لتغيير اللون"
                        />
                      )}
                    </TableCell>
                    <TableCell className="text-center font-bold">{orderCounts[s.id] || 0}</TableCell>
                    <TableCell>
                      <div className="flex gap-1 justify-center flex-wrap">
                        <Button size="sm" variant="outline" className="text-xs gap-1 h-7" onClick={() => startEditColor(s)}>
                          <Palette className="h-3 w-3" /> اللون
                        </Button>
                        <Button size="sm" variant="outline" className="text-xs gap-1 h-7" onClick={() => { setEditingNameId(s.id); setNameValue(s.name); }}>
                          <Pencil className="h-3 w-3" /> تعديل
                        </Button>
                        <Button size="sm" variant="destructive" className="text-xs gap-1 h-7" onClick={() => deleteStatus(s)}>
                          <Trash2 className="h-3 w-3" /> حذف
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
