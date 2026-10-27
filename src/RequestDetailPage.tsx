import { ArrowLeft, BriefcaseBusiness, Clock3, Flag, Users } from 'lucide-react'

type RequestItem = { id: string; task_id: string | null; requester_id: string; assignee_id: string; body: string; priority: string; due_date: string | null; status: string; created_at: string }
type Member = { user_id: string; display_name: string }
type Task = { id: string; title: string; description?: string }
type Props = { request: RequestItem; members: Member[]; tasks: Task[]; canUpdateStatus: boolean; onBack: () => void; onUpdateStatus: (status: string) => void }

export default function RequestDetailPage({ request, members, tasks, canUpdateStatus, onBack, onUpdateStatus }: Props) {
  const person = (id: string) => members.find(member => member.user_id === id)?.display_name || '팀원'
  const task = tasks.find(item => item.id === request.task_id)
  return <div className="content request-detail-content">
    <div className="page-heading"><div><div className="eyebrow">REQUEST DETAILS</div><h1>수정 요청 상세</h1><p>요청 내용과 담당자, 진행 상태를 확인할 수 있어요.</p></div><button className="button outline" onClick={onBack}><ArrowLeft size={15}/> 요청 목록</button></div>
    <article className="panel request-detail-card">
      <div className="request-card-head"><span className={`priority-pill ${request.priority === '높음' ? 'high' : ''}`}><Flag size={13}/>{request.priority} 우선순위</span><span className={`request-state state-${request.status}`}>{request.status}</span></div>
      <div className="request-detail-task"><BriefcaseBusiness size={17}/><div><small>관련 업무</small><h2>{task?.title || '연결된 업무 없음'}</h2>{task?.description && <p>{task.description}</p>}</div></div>
      <section className="request-detail-body"><h3>구체적인 수정 내용</h3><p>{request.body}</p></section>
      <div className="request-detail-meta"><div><Users size={16}/><span><small>요청자</small><b>{person(request.requester_id)}</b></span></div><div><Users size={16}/><span><small>담당자</small><b>{person(request.assignee_id)}</b></span></div><div><Clock3 size={16}/><span><small>요청일</small><b>{new Date(request.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })}</b></span></div>{request.due_date && <div><Clock3 size={16}/><span><small>희망 완료일</small><b>{request.due_date}</b></span></div>}</div>
      {canUpdateStatus && <div className="request-detail-status"><label htmlFor="request-detail-status">요청 상태</label><select id="request-detail-status" value={request.status} onChange={event => onUpdateStatus(event.target.value)}><option>보냄</option><option>확인함</option><option>진행 중</option><option>완료</option><option>보류</option></select></div>}
    </article>
  </div>
}
