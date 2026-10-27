import { ArrowRight, Bell, CheckCheck, Clock3 } from 'lucide-react'

export type NotificationItem = { id: string; type: string; title: string; body: string; entity_id: string | null; route: string; created_at: string; read_at: string | null }
type Props = { notifications: NotificationItem[]; onOpen: (item: NotificationItem) => void; onMarkRead: (item: NotificationItem) => void; onMarkAllRead: () => void }

export default function NotificationsPage({ notifications, onOpen, onMarkRead, onMarkAllRead }: Props) {
  const unread = notifications.filter(item => !item.read_at).length
  return <div className="content notifications-content">
    <div className="page-heading"><div><div className="eyebrow">NOTIFICATION HISTORY</div><h1>알림 기록</h1><p>출퇴근 인증, 퇴근 보고, 수정 요청과 댓글 알림을 모아봤어요.</p></div>{unread > 0 && <button className="button outline" onClick={onMarkAllRead}><CheckCheck size={16}/> 모두 읽음 처리</button>}</div>
    <div className="notification-history-list">{notifications.map(item => <button type="button" className={`notification-history-item ${item.read_at ? 'is-read' : 'is-unread'}`} key={item.id} onClick={() => onOpen(item)}>
      <span className="notification-history-icon"><Bell size={17}/></span><span className="notification-history-copy"><b>{item.title}</b><span>{item.body}</span><small><Clock3 size={13}/>{new Date(item.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</small></span><ArrowRight size={16}/>{!item.read_at && <i aria-label="읽지 않음"/>}
    </button>)}{!notifications.length && <div className="empty-state"><Bell size={28}/><b>아직 알림이 없어요</b><span>팀에 새 출퇴근 기록이나 퇴근 보고, 수정 요청이 등록되면 여기에 보여요.</span></div>}</div>
  </div>
}
