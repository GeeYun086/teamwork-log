import { ArrowRight, Clock3, MessageSquareText, Plus, Users } from 'lucide-react'

type RequestItem = { id: string; task_id: string | null; requester_id: string; assignee_id: string; body: string; priority: string; due_date: string | null; status: string; created_at: string }
type Member = { user_id: string; display_name: string }
type Task = { id: string; title: string }
type Props = {
  requests: RequestItem[]
  allCount: number
  allLabel: string
  pendingCount: number
  showTeamAll: boolean
  sentCount: number
  receivedCount: number
  scope: 'received' | 'sent' | 'all'
  members: Member[]
  tasks: Task[]
  onScopeChange: (scope: 'received' | 'sent' | 'all') => void
  onCreate: () => void
  onOpen: (request: RequestItem) => void
}

export default function RequestsPage({ requests, allCount, allLabel, pendingCount, showTeamAll, sentCount, receivedCount, scope, members, tasks, onScopeChange, onCreate, onOpen }: Props) {
  const person = (id: string) => members.find(member => member.user_id === id)?.display_name || '팀원'
  return <div className="content">
    <div className="page-heading"><div><div className="eyebrow">TEAM FEEDBACK</div><h1>수정 요청</h1><p>내가 보낸 요청과 팀원이 나에게 보낸 요청을 나눠서 확인해요.</p></div><button className="button primary" onClick={onCreate}><Plus size={16}/> 요청 보내기</button></div>
    <div className="request-filter-tabs" role="tablist" aria-label="수정 요청 구분">
      {showTeamAll && <button type="button" role="tab" aria-selected={scope === 'all'} className={scope === 'all' ? 'active' : ''} onClick={() => onScopeChange('all')}>팀 전체 <span>{allCount}</span></button>}
      <button type="button" role="tab" aria-selected={scope === 'received'} className={scope === 'received' ? 'active' : ''} onClick={() => onScopeChange('received')}>받은 요청 <span>{receivedCount}</span></button>
      <button type="button" role="tab" aria-selected={scope === 'sent'} className={scope === 'sent' ? 'active' : ''} onClick={() => onScopeChange('sent')}>보낸 요청 <span>{sentCount}</span></button>
      <small>{allLabel} {allCount}건 · {pendingCount}건 확인 대기</small>
    </div>
    <div className="request-cards">{requests.map(request => {
      const taskTitle = tasks.find(task => task.id === request.task_id)?.title || '연결된 업무 없음'
      const high = request.priority === '높음'
      return <article className="request-card" key={request.id}>
        <div className="request-card-head"><span className={`priority-pill ${high ? 'high' : ''}`}>{request.priority} 우선순위</span><span className={`request-state state-${request.status}`}>{request.status}</span></div>
        <button type="button" className="request-card-main" onClick={() => onOpen(request)}>
          <h2>{taskTitle}</h2><p>{request.body}</p>
          <span className="request-open-hint">요청 내용 자세히 보기 <ArrowRight size={14}/></span>
        </button>
        <div className="request-context"><span><Users size={14}/>{person(request.requester_id)} → {person(request.assignee_id)}</span><span><Clock3 size={14}/>{new Date(request.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>{request.due_date && <span>희망 완료일 {request.due_date}</span>}</div>
      </article>
    })}{!requests.length && <div className="empty-state"><MessageSquareText size={28}/><b>{scope === 'all' ? '팀 수정 요청이 없어요' : scope === 'received' ? '받은 수정 요청이 없어요' : '보낸 수정 요청이 없어요'}</b><span>{scope === 'all' ? '팀원이 요청을 등록하면 여기에 표시됩니다.' : scope === 'received' ? '팀원이 나에게 요청을 보내면 여기에 표시됩니다.' : '새 수정 요청을 보내면 여기에서 상태를 확인할 수 있어요.'}</span></div>}</div>
  </div>
}
